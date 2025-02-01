const std = @import("std");
const Node = @import("node.zig");
const World = @import("world.zig");
const UpdateStage = @import("universe.zig").UpdateStage;
const Transform = @import("../transform.zig");
const utils = @import("../utils.zig");

pub const Systems = @import("game.zig").EntitySystems;
pub const ParallelUpdateData = struct { stage: UpdateStage, world: *const World, entity: *Self, delta_time: f32 };
pub const ExclusiveUpdateData = struct { stage: UpdateStage, world: *World, entity: *Self, delta_time: f32 };

const EntitySystem = @import("enitty_system.zig");

const Pool = @import("../containers.zig").HandlePool(*Self);

const Self = @This();

pub const Handle = u64;

handle: Handle,
world_handle: ?World.Handle = null,

name: ?std.ArrayList(u8) = null,
transform: Transform = .{},

nodes: Node.Nodes,

systems: EntitySystem.Systems,

pub fn init(allocator: std.mem.Allocator, handle: Handle) Self {
    return .{
        .handle = handle,
        .nodes = Node.Nodes.init(allocator),
        .systems = EntitySystem.Systems.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    if (self.name) |name| {
        name.deinit();
    }
    self.nodes.deinit();
    self.systems.deinit();
}

pub fn updateParallel(self: *Self, stage: UpdateStage, world: *const World, delta_time: f32) void {
    self.systems.updateParallel(stage, self, world, delta_time);
}

pub fn updateExclusive(self: *Self, stage: UpdateStage, world: *World, delta_time: f32) void {
    self.systems.updateExclusive(stage, self, world, delta_time);
}

//TODO: Implement this in world update scheduling
pub const UpdateMode = enum {
    // Update every frame both in parallel pass and exclusive lock on the world
    exclusive_and_parallel,

    // Update every frame in parallel with other entities, world is const
    parallel,

    // Never runs update, used for static objects
    never,
};
