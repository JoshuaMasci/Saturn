const std = @import("std");

const Transform = @import("transform.zig");
const ObjectPool = @import("object_pool.zig").ObjectPool;
const renderer = @import("renderer.zig");

pub const StaticMeshInstance = struct {
    transform: Transform,
    mesh: renderer.StaticMeshHandle,
    material: std.BoundedArray(renderer.MaterialHandle, 16),
};

const StaticMeshInstancePool = ObjectPool(u16, StaticMeshInstance);
pub const StaticMeshInstanceHandle = StaticMeshInstancePool.Handle;

pub const Scene = struct {
    const Self = @This();

    static_meshes: StaticMeshInstancePool,
};
