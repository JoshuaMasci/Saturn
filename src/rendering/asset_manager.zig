const std = @import("std");
const ObjectPool = @import("../object_pool.zig").ObjectPool;

const StaticMeshSource = union(enum) {
    file: std.ArrayList(u8),
};
const StaticMeshSourcePool = ObjectPool(u16, StaticMeshSource);

const HandleType = u64;

pub const StaticMeshHandle = HandleType;
pub const SkeletalMeshHandle = HandleType;

pub const TextureHandle = HandleType;
pub const CubeTextureHandle = HandleType;

pub const ShaderHandle = HandleType;
pub const MaterialInstaceHandle = HandleType;

pub const RenderingAssetManager = struct {
    const Self = @This();

    static_mesh_asset_pool: ObjectPool(),

    pub fn getStaticMeshHandleFile(self: *Self, file_path: []const u8) !StaticMeshHandle {
        _ = file_path; // autofix
        _ = self; // autofix
    }
};
