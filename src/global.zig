const std = @import("std");

const MaterialRegistry = @import("asset/material.zig").Registry;
const MeshRegistry = @import("asset/mesh.zig").Registry;
const AssetRegistry = @import("asset/registry.zig");
const AssetSystem = @import("asset/system.zig");
const TextureRegistry = @import("asset/texture.zig").Registry;

pub var global_allocator: std.mem.Allocator = undefined;

const Assets = struct {
    const Self = @This();

    meshes: MeshRegistry,
    textures: TextureRegistry,
    materials: MaterialRegistry,
    registry: AssetRegistry,

    fn init(allocator: std.mem.Allocator) Self {
        return .{
            .meshes = .init(allocator),
            .textures = .init(allocator),
            .materials = .init(allocator),
            .registry = .init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.meshes.deinit();
        self.textures.deinit();
        self.materials.deinit();
        self.registry.deinit();
    }

    pub fn addDir(self: *Self, repo_name: []const u8, dir_path: []const u8) !void {
        const repo_hash = AssetSystem.HashMethod(repo_name);
        try self.meshes.addDir(repo_hash, dir_path);
        try self.textures.addDir(repo_hash, dir_path);
        try self.materials.addDir(repo_hash, dir_path);
        try self.registry.addRepository(repo_name, dir_path);
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

    global_allocator = undefined;
}
