const std = @import("std");

const MaterialAsset = @import("../asset/material.zig");
const AssetRegistry = @import("../asset/registry.zig");
const AssetPool = @import("asset_pool.zig");
const TextureAssetHandle = AssetPool.TextureAssetHandle;
const AlphaMode = MaterialAsset.AlphaMode;

pub const LoadSettings = struct {};

const Self = @This();

name: []const u8,

alpha_mode: AlphaMode = .@"opaque",
alpha_cutoff: f32 = 0.0,

base_color_texture: ?TextureAssetHandle = null,
base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

metallic_roughness_texture: ?TextureAssetHandle = null,
metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

emissive_texture: ?TextureAssetHandle = null,
emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

occlusion_texture: ?TextureAssetHandle = null,
normal_texture: ?TextureAssetHandle = null,

pub fn load(allocator: std.mem.Allocator, pool: *AssetPool, asset_handle: AssetRegistry.Handle, settings: LoadSettings) !Self {
    _ = settings; // autofix

    const asset = try pool.registry.loadAsset(MaterialAsset, allocator, asset_handle, .{});

    return .{
        .name = asset.name,

        .alpha_mode = asset.alpha_mode,
        .alpha_cutoff = asset.alpha_cutoff,

        .base_color_texture = loadTexture(pool, asset.base_color_texture),
        .base_color_factor = asset.base_color_factor,

        .metallic_roughness_texture = loadTexture(pool, asset.metallic_roughness_texture),
        .metallic_roughness_factor = asset.metallic_roughness_factor,

        .emissive_texture = loadTexture(pool, asset.emissive_texture),
        .emissive_factor = asset.emissive_factor,

        .occlusion_texture = loadTexture(pool, asset.occlusion_texture),
        .normal_texture = loadTexture(pool, asset.normal_texture),
    };
}

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
}

fn loadTexture(pool: *AssetPool, tex_opt: ?AssetRegistry.Handle) ?TextureAssetHandle {
    return pool.getTextureAsset(tex_opt orelse return null) catch null;
}
