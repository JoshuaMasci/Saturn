const std = @import("std");
const global = @import("global.zig");

const za = @import("zalgebra");
const Transform = @import("transform.zig");

const physics_system = @import("physics");

const Universe = @import("entity/universe.zig");
const World = @import("entity/world.zig");
const Entity = @import("entity/entity.zig");
const physics = @import("entity/engine/physics.zig");
const rendering = @import("entity/engine/rendering.zig");
const DebugCameraEntitySystem = @import("entity/engine//debug_camera.zig").DebugCameraEntitySystem;

const MeshAssetHandle = @import("asset/mesh.zig").Registry.Handle;
const MaterialAssetHandle = @import("asset/material.zig").Registry.Handle;

pub fn create_debug_camera(universe: *Universe, world_opt: ?World.Handle) !Entity.Handle {
    var entity = universe.createEntity();
    entity.transform.position = za.Vec3.Z.scale(1.0);
    entity.systems.add(DebugCameraEntitySystem{ .pitch_yaw = za.Vec2.new(0.0, std.math.pi) });
    entity.systems.add(physics.PhysicsEntitySystem.init(entity.handle, .dynamic));
    var root_node = entity.nodes.addNode(null, .{});

    root_node.components.add(@import("rendering/camera.zig").PerspectiveCamera{});
    root_node.components.add(physics.PhysicsColliderComponent{ .shape = physics_system.Shape.initSphere(0.25, 1.0, 0) });

    entity.systems.get(DebugCameraEntitySystem).?.camera_node = root_node.handle;
    entity.systems.get(physics.PhysicsEntitySystem).?.rebuildShape(entity);

    if (world_opt) |world| {
        universe.worlds.get(world).?.addEntity(entity);
    }

    return entity.handle;
}

pub fn create_ship_worlds(allocator: std.mem.Allocator, universe: *Universe) !struct {
    outside: World.Handle,
    inside: World.Handle,
} {
    var inside_world = universe.createWorld();
    inside_world.systems.add(physics.PhysicsWorldSystem.init());
    inside_world.systems.add(rendering.RenderWorldSystem.init(allocator));

    var outside_world = universe.createWorld();
    outside_world.systems.add(physics.PhysicsWorldSystem.init());
    outside_world.systems.add(rendering.RenderWorldSystem.init(allocator));

    var ship_inside = universe.createEntity();
    ship_inside.systems.add(physics.PhysicsEntitySystem.init(ship_inside.handle, .static));

    var ship_outside = universe.createEntity();
    ship_outside.systems.add(physics.PhysicsEntitySystem.init(ship_outside.handle, .dynamic));

    const bridge_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/bridge.mesh").?;
    const bridge_glass_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/bridge_glass.mesh").?;
    const hull_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/hull.mesh").?;
    const l_hull_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/l_hull.mesh").?;
    const engine_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/engine.mesh").?;
    const airlock_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/airlock2.mesh").?;
    const airlock_inside_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/airlock2_inside.mesh").?;

    const grid_material_handle = MaterialAssetHandle.fromRepoPath("engine:materials/grid.json_mat").?;
    const uv_grid_material_handle = MaterialAssetHandle.fromRepoPath("engine:materials/uv_grid.json_mat").?;

    try addMeshToEntites(allocator, ship_inside, ship_outside, bridge_mesh_handle, grid_material_handle, .{});
    try addMeshToEntites(allocator, ship_inside, ship_outside, bridge_glass_mesh_handle, grid_material_handle, .{});
    try addMeshToEntites(allocator, ship_inside, ship_outside, hull_mesh_handle, grid_material_handle, .{ .position = za.Vec3.NEG_Z.scale(5.0) });
    try addMeshToEntites(allocator, ship_inside, ship_outside, l_hull_mesh_handle, grid_material_handle, .{ .position = za.Vec3.NEG_Z.scale(15.0) });
    try addMeshToEntites(allocator, ship_inside, ship_outside, engine_mesh_handle, grid_material_handle, .{ .position = za.Vec3.NEG_Z.scale(20.0) });

    try addMeshToEntites(allocator, ship_inside, ship_outside, airlock_mesh_handle, grid_material_handle, .{ .position = za.Vec3.new(5.0, 0.0, -15.0), .rotation = za.Quat.fromEulerAngles(za.Vec3.new(0.0, za.toRadians(@as(f32, 90.0)), 0.0)) });
    try addMeshToEntites(allocator, ship_inside, ship_outside, airlock_inside_mesh_handle, uv_grid_material_handle, .{ .position = za.Vec3.new(2.5 + 1.25, 0.0, -15.0), .rotation = za.Quat.fromEulerAngles(za.Vec3.new(0.0, za.toRadians(@as(f32, 90.0)), 0.0)) });

    //Custom Airlock Shape
    // {
    //     const mesh = airlock_mesh_handle;
    //     const material = grid_material_handle;
    //     const transform: Transform = .{ .position = za.Vec3.new(5.0, 0.0, -15.0) };

    //     const airlock_shape = create_airlock_shape();

    //     var inside_node = ship_inside.nodes.addNode(null, transform);
    //     inside_node.components.add(rendering.StaticMeshComponent{ .mesh = mesh, .material = material });
    //     inside_node.components.add(physics.PhysicsColliderComponent{ .shape = airlock_shape });

    //     var outside_node = ship_outside.nodes.addNode(null, transform);
    //     outside_node.components.add(rendering.StaticMeshComponent{ .mesh = mesh, .material = material });
    //     outside_node.components.add(physics.PhysicsColliderComponent{ .shape = airlock_shape });
    // }

    // Airlock Doors
    {
        const mesh = MeshAssetHandle.fromRepoPath("engine:models/cube.mesh").?;
        const material = MaterialAssetHandle.fromRepoPath("engine:materials/teal.json_mat").?;

        const size = za.Vec3.new(0.25, 1.0, 1.0);

        const door_box = physics_system.Shape.initBox(size.data, 1.0, 0);

        const inside_airlock_center = ship_inside.nodes.addNode(null, .{ .position = za.Vec3.new(2.5 * 1.5, 0.0, -15.0) });
        const outside_airlock_center = ship_outside.nodes.addNode(null, .{ .position = za.Vec3.new(2.5 * 1.5, 0.0, -15.0) });

        const inside_parent = inside_airlock_center.handle;
        const outside_parent = outside_airlock_center.handle;

        var inside_node = ship_inside.nodes.addNode(inside_parent, .{ .position = za.Vec3.new(2.5 * 0.5, 0.0, 0.0), .scale = size });
        var outside_node = ship_outside.nodes.addNode(outside_parent, .{ .position = za.Vec3.new(-2.5 * 0.5, 0.0, 0.0), .scale = size });

        inside_node.components.add(rendering.StaticMeshComponent{ .mesh = mesh, .material = material });
        inside_node.components.add(physics.PhysicsColliderComponent{ .shape = door_box });
        inside_node.components.add(@import("entity/game.zig").AirLockComponent{ .center_node = inside_parent, .target = .{ .world = outside_world.handle, .entity = ship_outside.handle, .node = outside_parent } });

        outside_node.components.add(rendering.StaticMeshComponent{ .mesh = mesh, .material = material });
        outside_node.components.add(physics.PhysicsColliderComponent{ .shape = door_box });
        outside_node.components.add(@import("entity/game.zig").AirLockComponent{ .center_node = outside_parent, .target = .{ .world = inside_world.handle, .entity = ship_inside.handle, .node = inside_parent } });
    }

    ship_inside.systems.get(physics.PhysicsEntitySystem).?.rebuildShape(ship_inside);
    ship_outside.systems.get(physics.PhysicsEntitySystem).?.rebuildShape(ship_outside);

    inside_world.addEntity(ship_inside);
    outside_world.addEntity(ship_outside);

    return .{
        .outside = outside_world.handle,
        .inside = inside_world.handle,
    };
}

const PhysicsMeshes = struct {
    convex_shape: physics_system.Shape,
    mesh_shape: physics_system.Shape,

    fn fromHandle(allocator: std.mem.Allocator, handle: MeshAssetHandle) !@This() {
        var mesh = try global.assets.meshes.loadAsset(allocator, handle);
        defer mesh.deinit(allocator);

        var convex_shape = physics_system.Shape.initConvexHull(mesh.positions, 1.0, 0);
        defer convex_shape.deinit();

        const mass_properties = convex_shape.getMassProperties();
        const mesh_shape = physics_system.Shape.initMeshWithMass(mesh.positions, mesh.indices, mass_properties, 0);
        return .{
            .convex_shape = mesh_shape,
            .mesh_shape = mesh_shape,
        };
    }
};

fn addMeshToEntites(allocator: std.mem.Allocator, inside: *Entity, outside: *Entity, mesh: MeshAssetHandle, material: MaterialAssetHandle, transform: Transform) !void {
    std.debug.assert(global.assets.meshes.isValid(mesh));
    std.debug.assert(global.assets.materials.isValid(material));

    const mesh_shapes = try PhysicsMeshes.fromHandle(allocator, mesh);
    var inside_node = inside.nodes.addNode(null, transform);
    inside_node.components.add(rendering.StaticMeshComponent{ .mesh = mesh, .material = material });
    inside_node.components.add(physics.PhysicsColliderComponent{ .shape = mesh_shapes.mesh_shape });

    var outside_node = outside.nodes.addNode(null, transform);
    outside_node.components.add(rendering.StaticMeshComponent{ .mesh = mesh, .material = material });
    outside_node.components.add(physics.PhysicsColliderComponent{ .shape = mesh_shapes.convex_shape });
}

fn create_airlock_shape() physics_system.Shape {
    const ident_rot = [4]f32{ 0.0, 0.0, 0.0, 1.0 };

    var floor_box = physics_system.Shape.initBox(.{ 1.125, 0.25, 1.5 }, 1.0, 0);
    defer floor_box.deinit();

    var wall_box = physics_system.Shape.initBox(.{ 1.125, 1.0, 0.25 }, 1.0, 0);
    defer wall_box.deinit();

    const sub_shapes = [_]physics_system.SubShapeSettings{
        .{
            .shape = floor_box,
            .position = .{ -1.25, -1.25, 0.0 },
            .rotation = ident_rot,
        },
        .{
            .shape = floor_box,
            .position = .{ -1.25, 1.25, 0.0 },
            .rotation = ident_rot,
        },
        .{
            .shape = wall_box,
            .position = .{ -1.25, 0.0, 1.25 },
            .rotation = ident_rot,
        },
        .{
            .shape = wall_box,
            .position = .{ -1.25, 0.0, -1.25 },
            .rotation = ident_rot,
        },
    };

    return physics_system.Shape.initCompound(&sub_shapes, 0);
}
