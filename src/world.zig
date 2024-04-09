const std = @import("std");
const object_pool = @import("object_pool.zig");
const Transform = @import("transform.zig");

pub const NodePool = object_pool.ObjectPool(u16, Node);
pub const NodeHandle = NodePool.Handle;

pub const NodeComponents = struct {
    model: ?void,
    collider: ?void,
};

pub const Node = struct {
    name: ?[]const u8,
    local_transform: Transform,
    components: NodeComponents,

    parent: ?NodeHandle,
    childen: std.ArrayList(NodeHandle),
};

pub const EntityComponents = struct {
    character: ?void,
    rigid_body: ?void,
};

pub const EntityData = struct {
    name: ?[]const u8,
    transform: Transform,
    components: EntityComponents,

    root_nodes: std.ArrayList(NodeHandle),
    node_pool: NodePool,
};

pub const EntitySystems = struct {};
pub const Entity = struct {
    data: EntityData,
    systems: EntitySystems,
};

pub const WorldData = struct {};

pub const World = struct {
    data: WorldData,
    entity_pool: std.ArrayList(?Entity),
};
