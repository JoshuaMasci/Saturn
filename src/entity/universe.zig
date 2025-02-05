const std = @import("std");

const Transform = @import("../transform.zig");
const Node = @import("node.zig");
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

pub const EntityMoveTarget = struct {
    entity: ?Entity.Handle,
    node: ?Node.Handle,
    transform: Transform,
};

pub const EntityMove = struct {
    entity: Entity.Handle,
    target_world: World.Handle,
    target: ?EntityMoveTarget,
};

const Self = @This();

allocator: std.mem.Allocator,

entites: containers.HandlePtrPool(Entity.Handle, Entity),
worlds: containers.HandlePtrPool(World.Handle, World),

move_entity_list: std.ArrayList(EntityMove),

next_entity_handle: std.atomic.Value(Entity.Handle) = std.atomic.Value(Entity.Handle).init(1),
next_world_handle: std.atomic.Value(World.Handle) = std.atomic.Value(World.Handle).init(1),

pub fn init(allocator: std.mem.Allocator) !*Self {
    const ptr = try allocator.create(Self);
    ptr.* = .{
        .allocator = allocator,
        .entites = containers.HandlePtrPool(Entity.Handle, Entity).init(allocator),
        .worlds = containers.HandlePtrPool(World.Handle, World).init(allocator),
        .move_entity_list = std.ArrayList(EntityMove).init(allocator),
    };
    return ptr;
}

pub fn deinit(self: *Self) void {
    self.move_entity_list.deinit();
    self.worlds.deinit();
    self.entites.deinit();
    self.allocator.destroy(self);
}

pub fn scheduleMove(self: *Self, entity: Entity.Handle, target_world: World.Handle, target: ?EntityMoveTarget) void {
    self.move_entity_list.append(.{ .entity = entity, .target_world = target_world, .target = target }) catch |err| std.debug.panic("Failed to append to move entity list: {}", .{err});
}

pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
    if (stage == .frame_start) {
        for (self.move_entity_list.items) |move_entity| {
            const entity = self.entites.get(move_entity.entity).?;

            if (entity.world) |world| {
                world.removeEntity(entity);
            }

            if (move_entity.target) |target| {
                var transform = target.transform;

                if (target.entity) |entity_handle| {
                    const target_entity = self.entites.get(entity_handle).?;
                    var entity_transform = target_entity.transform;
                    if (target.node) |node_handle| {
                        entity_transform = entity_transform.applyTransform(&target_entity.nodes.getNodeRootTransform(node_handle).?);
                    }
                    transform = entity_transform.applyTransform(&transform);
                }

                entity.transform = transform;
            }

            const target_world = self.worlds.get(move_entity.target_world).?;
            target_world.addEntity(entity);
        }
        self.move_entity_list.clearRetainingCapacity();
    }

    const worlds = self.worlds.getValues(self.allocator);
    defer self.allocator.free(worlds);
    for (worlds) |world| {
        world.update(stage, delta_time);
    }
}

pub fn createEntity(self: *Self) *Entity {
    const handle = self.next_entity_handle.fetchAdd(1, .monotonic); //TODO: is this the correct atomic order?
    const entity = self.entites.create(handle);
    entity.* = Entity.init(self.allocator, self, handle);
    return entity;
}

pub fn createWorld(self: *Self) *World {
    const handle = self.next_world_handle.fetchAdd(1, .monotonic); //TODO: is this the correct atomic order?
    const world = self.worlds.create(handle);
    world.* = World.init(self.allocator, self, handle) catch |err| std.debug.panic("Failed to init world: {}", .{err});
    return world;
}
