const std = @import("std");
const testing = std.testing;

const HashType = u32;
pub const HashMethod = std.hash.Fnv1a_32.hash;

fn doesStringContain(strings: []const []const u8, key: []const u8) bool {
    for (strings) |pattern| {
        if (std.mem.eql(u8, pattern, key))
            return true;
    }
    return false;
}

pub const DirectoryRepository = struct {
    const Self = @This();

    const FileInfo = struct {
        file_path: []const u8,
    };

    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    assets: std.AutoHashMap(HashType, FileInfo),

    pub fn init(allocator: std.mem.Allocator, dir_path: []const u8, extesnions: []const []const u8) !Self {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        var assets = std.AutoHashMap(HashType, FileInfo).init(allocator);

        while (try walker.next()) |entry| {
            if (entry.kind == .file) {
                const extesnion = std.fs.path.extension(entry.path);
                if (doesStringContain(extesnions, extesnion)) {
                    const asset_hash = HashMethod(entry.path);
                    const path = try allocator.alloc(u8, entry.path.len);
                    @memcpy(path, entry.path);
                    try assets.put(asset_hash, .{ .file_path = path });
                }
            }
        }

        return .{
            .allocator = allocator,
            .dir = dir,
            .assets = assets,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.assets.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.file_path);
        }
        self.assets.deinit();
    }

    pub fn getAssetFile(self: Self, handle: HashType) !?std.fs.File {
        if (self.assets.getPtr(handle)) |asset| {
            return try self.dir.openFile(asset.file_path, .{ .mode = .read_only });
        }

        return null;
    }
};

pub fn AssetSystem(comptime T: type, comptime extesnions: []const []const u8) type {
    return struct {
        const Self = @This();

        pub const Handle = struct {
            repo_hash: HashType,
            asset_hash: HashType,

            pub fn fromRepoPath(repo_path: []const u8) ?Handle {
                var split = std.mem.splitSequence(u8, repo_path, ":");
                const repo = split.next() orelse return null;
                const path = split.next() orelse return null;
                const repo_hash = HashMethod(repo);
                const asset_hash = HashMethod(path);
                return .{ .repo_hash = repo_hash, .asset_hash = asset_hash };
            }

            pub fn fromRepoPathSeprate(repo: []const u8, path: []const u8) Handle {
                const repo_hash = HashMethod(repo);
                const asset_hash = HashMethod(path);
                return .{ .repo_hash = repo_hash, .asset_hash = asset_hash };
            }

            pub fn toU64(self: Handle) u64 {
                return (@as(u64, self.repo_hash) << 32) | @as(u64, self.asset_hash);
            }

            pub fn fromU64(id: u64) Handle {
                return .{
                    .repo_hash = @intCast(id >> 32),
                    .asset_hash = @intCast(id & 0xFFFF_FFFF),
                };
            }
        };

        allocator: std.mem.Allocator,
        repositories: std.AutoHashMap(HashType, DirectoryRepository),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .repositories = std.AutoHashMap(HashType, DirectoryRepository).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.repositories.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.repositories.deinit();
        }

        pub fn addDir(self: *Self, repo_hash: HashType, dir_path: []const u8) !void {
            const repo = try DirectoryRepository.init(self.allocator, dir_path, extesnions);
            try self.repositories.putNoClobber(repo_hash, repo);
        }

        pub fn isValid(self: Self, handle: Handle) bool {
            if (self.repositories.get(handle.repo_hash)) |repository| {
                return repository.assets.contains(handle.asset_hash);
            }
            return false;
        }

        pub fn loadAsset(self: Self, allocator: std.mem.Allocator, handle: Handle) !T {
            if (self.repositories.get(handle.repo_hash)) |repository| {
                if (try repository.getAssetFile(handle.asset_hash)) |asset_file| {
                    defer asset_file.close();
                    return try T.deserialzie(allocator, asset_file.reader());
                }
            }
            return error.InvaildAsset;
        }
    };
}
