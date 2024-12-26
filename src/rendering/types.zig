const asset = @import("../asset.zig");

pub const Material = struct {
    base_color_texture: ?asset.TextureAssetHandle = null,
    base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

    metallic_roughness_texture: ?asset.TextureAssetHandle = null,
    metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

    emissive_texture: ?asset.TextureAssetHandle = null,
    emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

    occlusion_texture: ?asset.TextureAssetHandle = null,
    normal_texture: ?asset.TextureAssetHandle = null,
};
