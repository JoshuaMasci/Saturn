const std = @import("std");

const AssetSystem = @import("asset/system.zig");
const MeshRegistry = @import("asset/mesh.zig").Registry;
const TextureRegistry = @import("asset/texture_2d.zig").Registry;

pub var global_allocator: std.mem.Allocator = undefined;

const Assets = struct {
    const Self = @This();

    meshes: MeshRegistry,
    textures: TextureRegistry,

    fn init(allocator: std.mem.Allocator) Self {
        return .{
            .meshes = MeshRegistry.init(allocator),
            .textures = TextureRegistry.init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.meshes.deinit();
        self.textures.deinit();
    }

    pub fn addDir(self: *Self, repo_name: []const u8, dir_path: []const u8) !void {
        const repo_hash = AssetSystem.HashMethod(repo_name);
        try self.meshes.addDir(repo_hash, dir_path);
        try self.textures.addDir(repo_hash, dir_path);
    }
};
pub var assets: *Assets = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    global_allocator = allocator;

    assets = try allocator.create(Assets);
    assets.* = Assets.init(allocator);
}

pub fn deinit() void {
    assets.deinit();
    global_allocator.destroy(assets);
}
