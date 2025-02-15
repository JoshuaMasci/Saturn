const std = @import("std");
const utils = @import("../utils.zig");

const Entity = @import("entity.zig");
const Universe = @import("universe.zig");
const UpdateStage = Universe.UpdateStage;

const WorldSystem = @import("world_system.zig");

pub const Handle = u32;

const Self = @This();

const EntityList = std.AutoArrayHashMap(Entity.Handle, *Entity);

allocator: std.mem.Allocator,
universe: *Universe,
handle: Handle,
root_entities: EntityList,
entities: EntityList,
systems: WorldSystem.Systems,

pub fn init(allocator: std.mem.Allocator, universe: *Universe, handle: Handle) !Self {
    return .{
        .allocator = allocator,
        .universe = universe,
        .handle = handle,
        .root_entities = EntityList.init(allocator),
        .entities = EntityList.init(allocator),
        .systems = WorldSystem.Systems.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.root_entities.values()) |entity| {
        self.deinitEntity(entity);
    }

    self.root_entities.deinit();
    self.entities.deinit();
    self.systems.deinit();
}

//Same as removeEntity but doesn't modify the lists
fn deinitEntity(self: *Self, entity: *Entity) void {
    for (entity.children.values()) |child| {
        self.deinitEntity(child);
    }
    self.systems.deregisterEntity(self, entity);
    entity.world = null;
}

pub fn addEntity(self: *Self, entity: *Entity) void {
    std.debug.assert(entity.world == null);

    if (entity.parent == null) {
        self.root_entities.put(entity.handle, entity) catch std.debug.panic("Failed to push entity to entity list", .{});
    }
    self.entities.put(entity.handle, entity) catch std.debug.panic("Failed to push entity to entity list", .{});

    entity.world = self;
    self.systems.registerEntity(self, entity);

    for (entity.children.values()) |child| {
        self.addEntity(child);
    }
}

pub fn removeEntity(self: *Self, entity: *Entity) void {
    std.debug.assert(entity.world.?.handle == self.handle);

    for (entity.children.values()) |child| {
        self.removeEntity(child);
    }
    self.systems.deregisterEntity(self, entity);
    entity.world = null;

    _ = self.entities.swapRemove(entity.handle);
    if (entity.parent == null) {
        _ = self.root_entities.swapRemove(entity.handle);
    }
}

pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
    //TODO: run in parallel
    for (self.root_entities.values()) |entity| {
        entity.updateParallel(stage, delta_time);
        entity.updateExclusive(stage, delta_time);
    }
    self.systems.update(self.allocator, stage, self, delta_time);
}
