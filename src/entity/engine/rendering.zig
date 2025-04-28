const std = @import("std");

const rendering_scene = @import("../../rendering/scene.zig");
pub const MaterialArray = rendering_scene.MaterialArray;
pub const StaticMeshComponent = rendering_scene.StaticMeshComponent;
const Entity = @import("../entity.zig");
const UpdateStage = @import("../universe.zig").UpdateStage;
const World = @import("../world.zig");

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

    pub fn registerEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix
        _ = entity; // autofix
        _ = self; // autofix
    }

    pub fn deregisterEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix
        _ = entity; // autofix
        _ = self; // autofix
    }

    pub fn update(self: *Self, stage: UpdateStage, world: *World, delta_time: f32) void {
        _ = delta_time; // autofix

        if (stage != .pre_render)
            return;

        self.scene.clear();

        for (world.entities.values()) |entity| {
            updateEntityInstances(&self.scene, entity) catch |err| std.debug.panic("Failed to update scene entity: {}", .{err});
        }
    }

    fn updateEntityInstances(scene: *rendering_scene.RenderScene, entity: *const Entity) !void {
        if (entity.systems.get(StaticMeshComponent)) |static_mesh_component| {
            const world_transform = entity.getWorldTransform();
            try scene.static_meshes.append(.{
                .transform = world_transform,
                .component = static_mesh_component.*,
            });
        }

        for (entity.children.values()) |child| {
            try updateEntityInstances(scene, child);
        }
    }
};
