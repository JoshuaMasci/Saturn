const std = @import("std");
const utils = @import("../utils.zig");

const Entity = @import("entity.zig");
const Universe = @import("universe.zig");
const UpdateStage = Universe.UpdateStage;

const WorldSystem = @import("world_system.zig");

pub const Handle = u32;

const Self = @This();

allocator: std.mem.Allocator,
universe: *Universe,
handle: Handle,
entities: std.AutoArrayHashMap(Entity.Handle, *Entity),
systems: WorldSystem.Systems,

pub fn init(allocator: std.mem.Allocator, universe: *Universe, handle: Handle) !Self {
    return .{
        .allocator = allocator,
        .universe = universe,
        .handle = handle,
        .entities = std.AutoArrayHashMap(Entity.Handle, *Entity).init(allocator),
        .systems = WorldSystem.Systems.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.entities.values()) |entity| {
        self.systems.deregisterEntity(self, entity);
        entity.world = null;
    }

    self.entities.deinit();
    self.systems.deinit();
}

pub fn addEntity(self: *Self, entity: *Entity) void {
    std.debug.assert(entity.world == null);
    self.entities.put(entity.handle, entity) catch std.debug.panic("Failed to push entity to entity list", .{});
    self.systems.registerEntity(self, entity);
    entity.world = self;
}

pub fn removeEntity(self: *Self, entity: *Entity) void {
    std.debug.assert(entity.world != null);
    const result = self.entities.fetchSwapRemove(entity.handle);
    if (result) |_| {
        self.systems.deregisterEntity(self, entity);
        entity.world = null;
    }
}

pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
    //TODO: run in parallel
    for (self.entities.values()) |entity| {
        entity.updateParallel(stage, delta_time);
        entity.updateExclusive(stage, delta_time);
    }
    self.systems.update(self.allocator, stage, self, delta_time);
}
