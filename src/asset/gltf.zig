const std = @import("std");

const Texture2D = @import("texture_2d.zig");
const Mesh = @import("mesh.zig");

const zgltf = @import("zgltf");
const zstbi = @import("zstbi");

pub const File = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    scenes: []?Scene,

    default_scene: ?usize = null,

    pub fn load(allocator: std.mem.Allocator, file_dir: std.fs.Dir, file_path: []const u8) !Self {
        var gltf_file = zgltf.init(allocator);
        defer gltf_file.deinit();

        //const parent_path = std.fs.path.dirname(file_path) orelse ".";

        const file_buffer = try file_dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
        defer allocator.free(file_buffer);
        try gltf_file.parse(file_buffer);

        //TODO: load .bin if not .glb

        var scenes = try allocator.alloc(?Scene, gltf_file.data.scenes.items.len);
        for (gltf_file.data.scenes.items, 0..) |*glft_scene, i| {
            scenes[i] = Scene.init(allocator, &gltf_file.data, glft_scene) catch |err| val: {
                std.log.err("Failed to load {s} scene {}: {}", .{ file_path, i, err });
                break :val null;
            };
        }

        return .{
            .allocator = allocator,
            .scenes = scenes,
            .default_scene = gltf_file.data.scene,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.scenes);
    }
};

pub const Scene = struct {
    const Self = @This();

    name: []u8,

    fn init(allocator: std.mem.Allocator, gltf_data: *const zgltf.Data, gltf_scene: *const zgltf.Scene) !Self {
        _ = gltf_data;

        return .{
            .name = try allocator.dupe(u8, gltf_scene.name),
        };
    }

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};
