const std = @import("std");
const Node = @import("node.zig");
const World = @import("world.zig");
const UpdateStage = @import("universe.zig").UpdateStage;
const Transform = @import("../transform.zig");
const utils = @import("../utils.zig");

pub const Systems = @import("game.zig").EntitySystems;
pub const UpdateData = struct { stage: UpdateStage, world: *const World, entity: *Self, delta_time: f32 };

const Self = @This();

pub const Handle = u64;
var next_handle = std.atomic.Value(Handle).init(1);

handle: Handle,

name: ?std.ArrayList(u8) = null,
transform: Transform = .{},

nodes: Node.Nodes,

systems: Systems = .{},

pub fn init(allocator: std.mem.Allocator, systems: Systems) Self {
    return .{
        .handle = next_handle.fetchAdd(1, .monotonic), //TODO: is this the correct atomic order?
        .nodes = Node.Nodes.init(allocator),
        .systems = systems,
    };
}

pub fn deinit(self: *Self) void {
    if (self.name) |name| {
        name.deinit();
    }
    self.nodes.deinit();
    self.systems.deinit();
}

pub fn update(self: *Self, stage: UpdateStage, world: *const World, delta_time: f32) void {
    self.systems.update(.{ .stage = stage, .world = world, .entity = self, .delta_time = delta_time });
}
