const std = @import("std");
const HashMethod = std.hash.Fnv1a_32.hash;

const AssetType = @import("header.zig").AssetType;
const HeaderV1 = @import("header.zig").HeaderV1;

const HashType = u32;

const AssetExtension: []const u8 = ".asset";
const AssetPackExtension: []const u8 = ".pak";

pub const AssetHandle = struct {
    repo_hash: HashType,
    asset_hash: HashType,

    pub fn fromRepoPath(repo: []const u8, path: []const u8) AssetHandle {
        const repo_hash = HashMethod(repo);
        const asset_hash = HashMethod(path);
        return .{ .repo_hash = repo_hash, .asset_hash = asset_hash };
    }

    pub fn toU64(self: AssetHandle) u64 {
        return (@as(u64, self.repo_hash) << 32) | @as(u64, self.asset_hash);
    }

    pub fn fromU64(id: u64) AssetHandle {
        return .{
            .repo_hash = @intCast(id >> 32),
            .asset_hash = @intCast(id & 0xFFFF_FFFF),
        };
    }
};

pub const AssetInfo = struct {
    file_path: []const u8,
    atype: AssetType,
    offset: usize,
    len: usize,
};

pub const Repository = struct {
    dir: std.fs.Dir,
    assets: std.AutoHashMap(HashType, AssetInfo),

    pub fn init(allocator: std.mem.Allocator, string_allocator: std.mem.Allocator, dir_path: []const u8) !Repository {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        var assets = std.AutoHashMap(HashType, AssetInfo).init(allocator);

        while (try walker.next()) |entry| {
            if (entry.kind == .file) {
                const file_extension = std.fs.path.extension(entry.path);
                if (std.mem.eql(u8, AssetExtension, file_extension) or true) {
                    var header: HeaderV1 = undefined;
                    const read_bytes = try dir.readFile(entry.path, std.mem.asBytes(&header));

                    if (read_bytes.len != @sizeOf(HeaderV1) or !header.valid()) {
                        continue;
                    }

                    const offset: usize = @sizeOf(HeaderV1);
                    const file_size = (try dir.statFile(entry.path)).size;

                    const file_path = try string_allocator.dupe(u8, entry.path);
                    const asset_hash = HashMethod(entry.path);
                    try assets.putNoClobber(asset_hash, .{
                        .file_path = file_path,
                        .atype = header.atype,
                        .offset = offset,
                        .len = file_size - offset,
                    });
                } else if (std.mem.eql(u8, AssetExtension, file_extension)) {
                    unreachable;
                }
            }
        }

        return .{
            .dir = dir,
            .assets = assets,
        };
    }

    pub fn deinit(self: *Repository) void {
        self.dir.close();
        self.assets.deinit();
    }
};

const Self = @This();

allocator: std.mem.Allocator,
string_arena: std.heap.ArenaAllocator,
repositories: std.AutoHashMap(HashType, Repository),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .string_arena = .init(allocator),
        .repositories = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.repositories.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit();
    }
    self.repositories.deinit();
    self.string_arena.deinit();
}

pub fn addRepository(self: *Self, repo_name: []const u8, dir_path: []const u8) !void {
    const repo = try Repository.init(self.allocator, self.string_arena.allocator(), dir_path);
    std.log.info("Loaded Asset Repo \"{s}\" with {} assets", .{ repo_name, repo.assets.count() });
    try self.repositories.putNoClobber(HashMethod(repo_name), repo);
}

pub fn loadAsset(
    self: *const Self,
    comptime T: type,
    allocator: std.mem.Allocator,
    handle: AssetHandle,
) !T {
    if (self.repositories.get(handle.repo_hash)) |repository| {
        if (repository.assets.get(handle.asset_hash)) |asset_info| {
            const asset_buffer = try loadAssetBuffer(allocator, repository.dir, asset_info);
            defer allocator.free(asset_buffer);

            var buffer_stream = std.io.fixedBufferStream(asset_buffer);
            const buffer_stream_reader = buffer_stream.reader();
            return try T.deserialzie(allocator, buffer_stream_reader);
        } else {
            return error.InvalidAssetHash;
        }
    } else {
        return error.InvalidRepoHash;
    }
}

fn loadAssetBuffer(allocator: std.mem.Allocator, dir: std.fs.Dir, asset_info: AssetInfo) ![]const u8 {
    const buffer = try allocator.alloc(u8, asset_info.len);
    errdefer allocator.free(buffer);

    //TODO: validate asset header (in debug builds only?)
    // Not really a huge deal since they are validated when the AssetInfo is generated
    // But might be useful if the file is modified after startup
    var file = try dir.openFile(asset_info.file_path, .{});
    defer file.close();

    try file.seekTo(asset_info.offset);
    const read_amount = try file.readAll(buffer);
    if (read_amount != asset_info.len) {
        return error.UnexpectedEOF;
    }

    return buffer;
}
