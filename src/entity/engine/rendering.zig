const std = @import("std");
const Entity = @import("../entity.zig");
const World = @import("../world.zig");
const UpdateStage = @import("../universe.zig").UpdateStage;

const rendering_scene = @import("../../rendering/scene.zig");

pub const RenderWorldSystem = struct {
    const Self = @This();

    scene: rendering_scene.RenderScene,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .scene = rendering_scene.RenderScene.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.scene.deinit();
    }

    pub fn registerEntity(self: *Self, data: World.EntityRegisterData) void {
        _ = self; // autofix
        _ = data; // autofix
    }

    pub fn update(self: *Self, data: World.UpdateData) void {
        if (data.stage != .pre_render)
            return;

        self.scene.clear();

        for (data.world.entities.values()) |entity| {
            updateEntityInstances(&self.scene, entity) catch |err| std.debug.panic("Failed to update scene entity: {}", .{err});
        }
    }

    fn updateEntityInstances(scene: *rendering_scene.RenderScene, entity: *const Entity) !void {
        var iter = entity.nodes.pool.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.components.static_mesh) |*static_mesh_component| {
                const root_transform = entity.nodes.getNodeRootTransform(entry.handle).?;
                const world_transform = entity.transform.transform_by(&root_transform);
                try scene.static_meshes.append(.{
                    .transform = world_transform,
                    .component = static_mesh_component.*,
                });
            }
        }
    }
};

pub const StaticMeshComponent = rendering_scene.StaticMeshComponent;
