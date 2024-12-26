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

    skybox: ?asset.CubeTextureAssetHandle = null,
    static_meshes: std.ArrayList(SceneStaticMesh),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .static_meshes = std.ArrayList(SceneStaticMesh).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.static_meshes.deinit();
    }

    pub fn clear(self: *Self) void {
        self.skybox = null;
        self.static_meshes.clearRetainingCapacity();
    }

    pub fn dupe(self: Self, allocator: std.mem.Allocator) !Self {
        var new_self = self;
        new_self.static_meshes = try std.ArrayList(SceneStaticMesh).initCapacity(allocator, self.static_meshes.items.len);
        new_self.static_meshes.appendSliceAssumeCapacity(self.static_meshes.items);
        return new_self;
    }
};
