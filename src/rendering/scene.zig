const std = @import("std");
const asset = @import("../asset.zig");

const Transform = @import("../transform.zig");

pub const StaticMeshComponent = struct {
    visable: bool = true,
    mesh: asset.MeshAssetHandle,
    material: asset.MaterialAssetHandle,
};

pub const SceneStaticMesh = struct {
    transform: Transform,
    component: StaticMeshComponent,
};

pub const RenderScene = struct {
    const Self = @This();

    skybox: ?asset.CubeMapTextureAssetHandle,
    static_meshes: std.BoundedArray(SceneStaticMesh, 1024),
};
