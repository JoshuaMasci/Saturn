const std = @import("std");

const Entity = @import("entity.zig");
const World = @import("world.zig");

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

//entites: std.AutoHashMap(Entity.Handle, Entity),
worlds: std.AutoHashMap(World.Handle, World),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .worlds = std.AutoHashMap(World.Handle, World).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.worlds.valueIterator();
    while (iter.next()) |world| {
        world.deinit();
    }
    self.worlds.deinit();
}

pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
    var iter = self.worlds.valueIterator();
    while (iter.next()) |world| {
        world.update(stage, delta_time);
    }
}

pub fn addWorld(self: *Self, world: World) !World.Handle {
    try self.worlds.putNoClobber(world.handle, world);
    return world.handle;
}

pub fn removeWorld(self: *Self, world_handle: World.Handle) ?World {
    std.debug.assert(self.worlds.contains(world_handle));
    if (self.worlds.fetchRemove(world_handle)) |entry| {
        return entry.value;
    }
    return null;
}
