pub const World = @import("world.zig");
pub const Entity = @import("entity.zig");

pub const AirLockComponent = struct {
    center_node: Entity.Handle,
    target: ?struct {
        world: World.Handle,
        entity: Entity.Handle,
    },
};

pub const AirLockEntitySystem = struct {};
