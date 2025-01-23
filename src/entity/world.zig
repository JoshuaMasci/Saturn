const std = @import("std");
const utils = @import("../utils.zig");
const LockQueue = @import("../lock_queue.zig").LockQueue;

const Entity = @import("entity.zig");
const UpdateStage = @import("universe.zig").UpdateStage;

pub const Systems = @import("game.zig").WorldSystems;
pub const UpdateData = struct { stage: UpdateStage, world: *Self, delta_time: f32 };
pub const EntityRegisterData = struct { world: *Self, entity: *Entity };

const Self = @This();

pub const Handle = u32;

allocator: std.mem.Allocator,
handle: Handle,
entities: std.AutoArrayHashMap(Entity.Handle, *Entity),
systems: Systems = .{},

pub fn init(allocator: std.mem.Allocator, handle: Handle) !Self {
    return .{
        .allocator = allocator,
        .handle = handle,
        .entities = std.AutoArrayHashMap(Entity.Handle, *Entity).init(allocator),
        .systems = .{},
    };
}

pub fn deinit(self: *Self) void {
    for (self.entities.values()) |entity| {
        self.systems.deregisterEntity(.{ .world = self, .entity = entity });
        entity.world_handle = null;
    }

    self.entities.deinit();
    self.systems.deinit();
}

pub fn addEntity(self: *Self, entity: *Entity) void {
    std.debug.assert(entity.world_handle == null);
    self.entities.put(entity.handle, entity) catch std.debug.panic("Failed to push entity to entity list", .{});
    self.systems.registerEntity(.{ .world = self, .entity = entity });
    entity.world_handle = self.handle;
}

pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
    //TODO: run in parallel
    for (self.entities.values()) |entity| {
        entity.updateParallel(stage, self, delta_time);
        entity.updateExclusive(stage, self, delta_time);
    }
    self.systems.update(.{ .stage = stage, .world = self, .delta_time = delta_time });
}
