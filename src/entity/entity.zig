const std = @import("std");
const Node = @import("node.zig");
const World = @import("world.zig");

const Universe = @import("universe.zig");
const UpdateStage = Universe.UpdateStage;

const Transform = @import("../transform.zig");
const utils = @import("../utils.zig");

const EntitySystem = @import("entity_system.zig");
const Pool = @import("../containers.zig").HandlePool(*Self);

pub const Handle = u64;

const Self = @This();

handle: Handle,
universe: *Universe,
world: ?*World = null,
name: ?std.ArrayList(u8) = null,
transform: Transform = .{},
nodes: Node.Nodes,
systems: EntitySystem.Systems,

pub fn init(allocator: std.mem.Allocator, universe: *Universe, handle: Handle) Self {
    return .{
        .universe = universe,
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

pub fn updateParallel(self: *Self, stage: UpdateStage, delta_time: f32) void {
    self.systems.updateParallel(stage, self, delta_time);
}

pub fn updateExclusive(self: *Self, stage: UpdateStage, delta_time: f32) void {
    self.systems.updateExclusive(stage, self, delta_time);
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
