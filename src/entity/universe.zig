const std = @import("std");

const Transform = @import("../transform.zig");
const Entity = @import("entity.zig");
const World = @import("world.zig");

const containers = @import("../containers.zig");

pub const UpdateStage = enum {
    frame_start,
    pre_physics,
    physics,
    post_physics,
    pre_render,
    frame_end,
};

pub const EntityMoveTarget = union(enum) {
    entity: Entity.Handle,
    world: World.Handle,
};

pub const EntityMove = struct {
    entity: Entity.Handle,
    target: EntityMoveTarget,
    offset: Transform,
};

const Self = @This();

allocator: std.mem.Allocator,

entities: containers.HandlePtrPool(Entity.Handle, Entity),
worlds: containers.HandlePtrPool(World.Handle, World),

move_entity_list: std.ArrayList(EntityMove),

next_entity_handle: std.atomic.Value(Entity.Handle) = std.atomic.Value(Entity.Handle).init(1),
next_world_handle: std.atomic.Value(World.Handle) = std.atomic.Value(World.Handle).init(1),

pub fn init(allocator: std.mem.Allocator) !*Self {
    const ptr = try allocator.create(Self);
    ptr.* = .{
        .allocator = allocator,
        .entities = containers.HandlePtrPool(Entity.Handle, Entity).init(allocator),
        .worlds = containers.HandlePtrPool(World.Handle, World).init(allocator),
        .move_entity_list = std.ArrayList(EntityMove).init(allocator),
    };
    return ptr;
}

pub fn deinit(self: *Self) void {
    self.move_entity_list.deinit();
    self.worlds.deinit();
    self.entities.deinit();
    self.allocator.destroy(self);
}

pub fn scheduleMove(self: *Self, entity: Entity.Handle, target: EntityMoveTarget, offset: Transform) void {
    self.move_entity_list.append(.{ .entity = entity, .target = target, .offset = offset }) catch |err| std.debug.panic("Failed to append to move entity list: {}", .{err});
}

pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
    if (stage == .frame_start) {
        for (self.move_entity_list.items) |move_entity| {
            const entity = self.entities.get(move_entity.entity).?;

            const old_world_handle = entity.world.?.handle;

            if (entity.world) |world| {
                world.removeEntity(entity);
            }

            var target_world: ?*World = null;
            var target_transform = move_entity.offset;

            switch (move_entity.target) {
                .entity => |target_handle| {
                    if (self.entities.get(target_handle)) |target_entity| {
                        target_world = target_entity.world;
                        target_transform = target_entity.getWorldTransform().applyTransform(&target_transform);
                    }
                },
                .world => |target_handle| {
                    if (self.worlds.get(target_handle)) |world| {
                        target_world = world;
                    }
                },
            }

            entity.transform = target_transform;

            if (target_world) |new_world| {
                std.debug.assert(old_world_handle != new_world.handle);

                new_world.addEntity(entity);
            }
        }
        self.move_entity_list.clearRetainingCapacity();
    }

    const worlds = self.worlds.getValues(self.allocator);
    defer self.allocator.free(worlds);
    for (worlds) |world| {
        world.update(stage, delta_time);
    }
}

pub fn createEntity(self: *Self, name: []const u8) *Entity {
    const handle = self.next_entity_handle.fetchAdd(1, .monotonic); //TODO: is this the correct atomic order?
    const entity = self.entities.create(handle);
    entity.* = Entity.init(self.allocator, self, handle, name);
    entity.*.root = entity;
    return entity;
}

pub fn createWorld(self: *Self) *World {
    const handle = self.next_world_handle.fetchAdd(1, .monotonic); //TODO: is this the correct atomic order?
    const world = self.worlds.create(handle);
    world.* = World.init(self.allocator, self, handle) catch |err| std.debug.panic("Failed to init world: {}", .{err});
    return world;
}
