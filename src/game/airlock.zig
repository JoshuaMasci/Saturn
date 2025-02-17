const std = @import("std");
pub const Transform = @import("../transform.zig");
pub const World = @import("../entity/world.zig");
pub const Entity = @import("../entity/entity.zig");

const jolt_physics = @import("physics");
const physics = @import("../entity/engine/physics.zig");

pub const AirLockComponent = struct {
    cast_layer: u16,
    cast_shape: ?jolt_physics.Shape = null,
    cast_offset: Transform = .{},
    linked_entity: ?Entity.Handle = null,

    pub fn moveEntites(self: @This(), temp_allocator: std.mem.Allocator, parent: *Entity) void {
        const world = parent.world.?;
        const physics_world = world.systems.get(physics.PhysicsWorldSystem) orelse return;
        const shape = self.cast_shape orelse return;

        var entity_list = physics_world.castShape(temp_allocator, self.cast_layer, shape, parent.getWorldTransform().applyTransform(&self.cast_offset));
        defer entity_list.deinit();

        var count: usize = 0;

        for (entity_list.items) |hit_handle| {
            const hit_entity = world.entities.get(hit_handle) orelse continue;
            if (hit_entity.root.handle != parent.root.handle) {
                count += 1;
                const relative_transform = parent.getWorldTransform().getRelativeTransform(&hit_entity.getWorldTransform());
                world.universe.scheduleMove(hit_entity.handle, .{ .entity = self.linked_entity.? }, relative_transform);
            }
        }
    }
};
