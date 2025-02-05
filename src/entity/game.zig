pub const World = @import("world.zig");
pub const Entity = @import("entity.zig");
pub const Node = @import("node.zig");

pub const AirLockComponent = struct {
    center_node: Node.Handle,
    target: ?struct {
        world: World.Handle,
        entity: Entity.Handle,
        node: Node.Handle,
    },
};
