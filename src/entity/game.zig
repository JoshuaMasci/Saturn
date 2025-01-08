pub const rendering = @import("engine/rendering.zig");
pub const physics = @import("engine/physics.zig");
pub const debug_camera = @import("engine/debug_camera.zig");

const PerspectiveCamera = @import("../rendering/camera.zig").PerspectiveCamera;

pub const WorldSystems = struct {
    render: ?rendering.RenderWorldSystem = null,
    physics: ?physics.PhysicsWorldSystem = null,
};

pub const EntitySystems = struct {
    physics: ?physics.PhysicsEntitySystem = null,
    debug_camera: ?debug_camera.DebugCameraEntitySystem = null,
};

pub const NodeComponents = struct {
    static_mesh: ?rendering.StaticMeshComponent = null,
    camera: ?PerspectiveCamera = null,
    collider: ?physics.PhysicsColliderComponent = null,
};
