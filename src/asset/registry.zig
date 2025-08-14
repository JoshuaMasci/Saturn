const std = @import("std");

const HeaderV1 = @import("header.zig").HeaderV1;
const AssetType = @import("header.zig").AssetType;

const HashMethod = std.hash.Fnv1a_32.hash;
const HashType = u32;

const AssetExtension: []const u8 = ".asset";
const AssetPackExtension: []const u8 = ".pak";

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

    fn deinit(self: *@This()) void {
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
