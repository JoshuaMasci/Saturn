const std = @import("std");
const utils = @import("../utils.zig");

const Entity = @import("entity.zig");
const UpdateStage = @import("universe.zig").UpdateStage;

pub const Systems = @import("game.zig").WorldSystems;
pub const UpdateData = struct { stage: UpdateStage, world: *Self, delta_time: f32 };
pub const EntityRegisterData = struct { world: *Self, entity: *Entity };

const Self = @This();

pub const Handle = u32;
var next_handle = std.atomic.Value(Handle).init(1);

allocator: std.mem.Allocator,
handle: Handle,
entities: std.AutoArrayHashMap(Entity.Handle, Entity),
systems: Systems = .{},

pub fn init(allocator: std.mem.Allocator, systems: Systems) !Self {
    return .{
        .allocator = allocator,
        .handle = next_handle.fetchAdd(1, .monotonic), //TODO: is this the correct atomic order?,
        .entities = std.AutoArrayHashMap(Entity.Handle, Entity).init(allocator),
        .systems = systems,
    };
}

pub fn deinit(self: *Self) void {
    for (self.entities.values()) |*entity| {
        entity.deinit();
    }

    self.entities.deinit();
    self.systems.deinit();
}

pub fn addEntity(self: *Self, entity: Entity) Entity.Handle {
    self.entities.put(entity.handle, entity) catch std.debug.panic("Failed to push entity to entity list", .{});
    const ptr: *Entity = self.entities.getPtr(entity.handle).?;
    self.systems.registerEntity(.{ .world = self, .entity = ptr });
    return entity.handle;
}

pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
    //TODO: run in parallel
    for (self.entities.values()) |*entity| {
        entity.updateParallel(stage, self, delta_time);
        entity.updateExclusive(stage, self, delta_time);
    }
    self.systems.update(.{ .stage = stage, .world = self, .delta_time = delta_time });
}
