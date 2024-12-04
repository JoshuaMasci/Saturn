const std = @import("std");

const HashType = u32;
const HashMethod = std.hash.Fnv1a_32;

const AssetMap = std.AutoHashMap(HashType, std.ArrayList(u8));

pub const FileAssetRegistry = struct {
    const Self = @This();

    map: AssetMap,

    pub fn initFromDir(allocator: std.mem.Allocator, dir_path: []const u8) !Self {
        var map = AssetMap.init(allocator);

        var asset_dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        var walker = try asset_dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind == .file) {
                var string = try std.ArrayList(u8).initCapacity(allocator, entry.path.len);
                string.appendSliceAssumeCapacity(entry.path);
                try map.put(HashMethod.hash(string.items), string);
            }
        }

        return .{ .map = map };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }

        self.map.deinit();
    }
};
