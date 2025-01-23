pub const rendering = @import("engine/rendering.zig");
pub const physics = @import("engine/physics.zig");
pub const debug_camera = @import("engine/debug_camera.zig");

const PerspectiveCamera = @import("../rendering/camera.zig").PerspectiveCamera;

const Entity = @import("entity.zig");

pub const WorldSystems = struct {
    const Self = @This();

    render: ?rendering.RenderWorldSystem = null,
    physics: ?physics.PhysicsWorldSystem = null,

    pub fn deinit(self: *Self) void {
        if (self.render) |*system| {
            system.deinit();
        }

        if (self.physics) |*system| {
            system.deinit();
        }
    }

    pub fn registerEntity(self: *Self, data: @import("world.zig").EntityRegisterData) void {
        if (self.render) |*system| {
            system.registerEntity(data);
        }

        if (self.physics) |*system| {
            system.registerEntity(data);
        }
    }

    pub fn deregisterEntity(self: *Self, data: @import("world.zig").EntityRegisterData) void {
        if (self.physics) |*system| {
            system.deregisterEntity(data);
        }
    }

    pub fn update(self: *Self, data: @import("world.zig").UpdateData) void {
        if (self.render) |*system| {
            system.update(data);
        }

        if (self.physics) |*system| {
            system.update(data);
        }
    }
};

pub const EntitySystems = struct {
    const Self = @This();

    physics: ?physics.PhysicsEntitySystem = null,
    debug_camera: ?debug_camera.DebugCameraEntitySystem = null,

    pub fn deinit(self: *Self) void {
        if (self.debug_camera) |*system| {
            system.deinit();
        }

        if (self.physics) |*system| {
            system.deinit();
        }
    }

    pub fn updateParallel(self: *Self, data: Entity.ParallelUpdateData) void {
        if (self.debug_camera) |*system| {
            system.updateParallel(data);
        }

        if (self.physics) |*system| {
            system.updateParallel(data);
        }
    }

    pub fn updateExclusive(self: *Self, data: Entity.ExclusiveUpdateData) void {
        if (self.debug_camera) |*system| {
            system.updateExclusive(data);
        }
    }
};

pub const AirLockComponent = struct {};

pub const NodeComponents = struct {
    static_mesh: ?rendering.StaticMeshComponent = null,
    camera: ?PerspectiveCamera = null,
    collider: ?physics.PhysicsColliderComponent = null,
    airlock: ?AirLockComponent = null,
};
