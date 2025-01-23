const std = @import("std");

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

const Self = @This();

allocator: std.mem.Allocator,

entites: containers.HandlePtrPool(Entity.Handle, Entity),
worlds: containers.HandlePtrPool(World.Handle, World),

next_entity_handle: std.atomic.Value(Entity.Handle) = std.atomic.Value(Entity.Handle).init(1),
next_world_handle: std.atomic.Value(World.Handle) = std.atomic.Value(World.Handle).init(1),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .entites = containers.HandlePtrPool(Entity.Handle, Entity).init(allocator),
        .worlds = containers.HandlePtrPool(World.Handle, World).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.worlds.deinit();
    self.entites.deinit();
}

pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
    const worlds = self.worlds.getValues(self.allocator);
    defer self.allocator.free(worlds);
    for (worlds) |world| {
        world.update(stage, delta_time);
    }
}

pub fn createEntity(self: *Self) *Entity {
    const handle = self.next_entity_handle.fetchAdd(1, .monotonic); //TODO: is this the correct atomic order?
    const entity = self.entites.create(handle);
    entity.* = Entity.init(self.allocator, handle);
    return entity;
}

pub fn createWorld(self: *Self) *World {
    const handle = self.next_world_handle.fetchAdd(1, .monotonic); //TODO: is this the correct atomic order?
    const world = self.worlds.create(handle);
    world.* = World.init(self.allocator, handle) catch |err| std.debug.panic("Failed to init world: {}", .{err});
    return world;
}
