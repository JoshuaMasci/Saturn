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

const MeshAssetHandle = @import("asset/mesh.zig").Registry.Handle;
const MaterialAssetHandle = @import("asset/material.zig").Registry.Handle;

pub fn create_debug_camera(allocator: std.mem.Allocator) !Entity {
    var entity = Entity.init(allocator, .{});
    entity.transform.position = za.Vec3.Z.scale(1.0);
    entity.systems.debug_camera = .{ .pitch_yaw = za.Vec2.new(0.0, std.math.pi) };
    entity.systems.physics = physics.PhysicsEntitySystem.init(entity.handle, .dynamic);
    entity.systems.debug_camera.?.camera_node = try entity.nodes.addNode(null, .{}, .{
        .camera = .{},
        .collider = .{ .shape = physics_system.Shape.initSphere(0.25, 1.0, 0) },
    });
    entity.systems.physics.?.rebuildShape(&entity);
    return entity;
}

pub fn create_ship_worlds(allocator: std.mem.Allocator) !struct {
    outside: World,
    inside: World,
} {
    var outside_world = try World.init(allocator, .{});
    outside_world.systems.physics = physics.PhysicsWorldSystem.init();
    outside_world.systems.render = rendering.RenderWorldSystem.init(allocator);

    var inside_world = try World.init(allocator, .{});
    inside_world.systems.physics = physics.PhysicsWorldSystem.init();
    inside_world.systems.render = rendering.RenderWorldSystem.init(allocator);

    var ship_inside = Entity.init(allocator, .{});
    ship_inside.systems.physics = physics.PhysicsEntitySystem.init(ship_inside.handle, .static);
    var ship_outside = Entity.init(allocator, .{});
    ship_outside.systems.physics = physics.PhysicsEntitySystem.init(ship_outside.handle, .dynamic);

    const bridge_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/bridge.mesh").?;
    const bridge_glass_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/bridge_glass.mesh").?;
    const hull_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/hull.mesh").?;
    const l_hull_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/l_hull.mesh").?;
    const engine_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/engine.mesh").?;
    const airlock_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/airlock.mesh").?;

    const grid_material_handle = MaterialAssetHandle.fromRepoPath("engine:materials/grid.json_mat").?;

    try addMeshToEntites(allocator, &ship_inside, &ship_outside, bridge_mesh_handle, grid_material_handle, .{});
    try addMeshToEntites(allocator, &ship_inside, &ship_outside, bridge_glass_mesh_handle, grid_material_handle, .{});
    try addMeshToEntites(allocator, &ship_inside, &ship_outside, hull_mesh_handle, grid_material_handle, .{ .position = za.Vec3.NEG_Z.scale(5.0) });
    try addMeshToEntites(allocator, &ship_inside, &ship_outside, l_hull_mesh_handle, grid_material_handle, .{ .position = za.Vec3.NEG_Z.scale(15.0) });
    try addMeshToEntites(allocator, &ship_inside, &ship_outside, engine_mesh_handle, grid_material_handle, .{ .position = za.Vec3.NEG_Z.scale(20.0) });

    //Custom Airlock Shape
    //    try addMeshToEntites(allocator, &ship_inside, &ship_outside, airlock_mesh_handle, grid_material_handle, .{ .position = za.Vec3.new(5.0, 0.0, -15.0) });
    {
        const mesh = airlock_mesh_handle;
        const material = grid_material_handle;
        const transform: Transform = .{ .position = za.Vec3.new(5.0, 0.0, -15.0) };

        const airlock_shape = create_airlock_shape();

        _ = try ship_inside.nodes.addNode(
            null,
            transform,
            .{
                .static_mesh = .{ .mesh = mesh, .material = material },
                .collider = .{ .shape = airlock_shape },
            },
        );

        _ = try ship_outside.nodes.addNode(
            null,
            transform,
            .{
                .static_mesh = .{ .mesh = mesh, .material = material },
                .collider = .{ .shape = airlock_shape },
            },
        );
    }

    // Airlock Doors
    {
        const mesh = MeshAssetHandle.fromRepoPath("engine:models/cube.mesh").?;
        const material = MaterialAssetHandle.fromRepoPath("engine:materials/teal.json_mat").?;

        const size = za.Vec3.new(0.25, 1.0, 1.0);

        const transform: Transform = .{ .position = za.Vec3.new(5.0, 0.0, -15.0), .scale = size };
        const door_box = physics_system.Shape.initBox(size.data, 1.0, 0);

        _ = try ship_inside.nodes.addNode(
            null,
            transform,
            .{
                .static_mesh = .{ .mesh = mesh, .material = material },
                .collider = .{ .shape = door_box },
                .airlock = .{},
            },
        );
    }

    ship_inside.systems.physics.?.rebuildShape(&ship_inside);
    ship_outside.systems.physics.?.rebuildShape(&ship_outside);

    _ = inside_world.addEntity(ship_inside);
    _ = outside_world.addEntity(ship_outside);

    return .{
        .outside = outside_world,
        .inside = inside_world,
    };
}

const PhysicsMeshes = struct {
    mesh_shape: physics_system.Shape,
    convex_shape: physics_system.Shape,

    fn fromHandle(allocator: std.mem.Allocator, handle: MeshAssetHandle) !@This() {
        var mesh = try global.assets.meshes.loadAsset(allocator, handle);
        defer mesh.deinit(allocator);

        return .{
            .mesh_shape = physics_system.Shape.initMesh(mesh.positions, mesh.indices, 0),
            .convex_shape = physics_system.Shape.initConvexHull(mesh.positions, 1.0, 0),
        };
    }
};

fn addMeshToEntites(allocator: std.mem.Allocator, inside: *Entity, outside: *Entity, mesh: MeshAssetHandle, material: MaterialAssetHandle, transform: Transform) !void {
    std.debug.assert(global.assets.meshes.isValid(mesh));
    std.debug.assert(global.assets.materials.isValid(material));

    const mesh_shapes = try PhysicsMeshes.fromHandle(allocator, mesh);
    _ = try inside.nodes.addNode(
        null,
        transform,
        .{
            .static_mesh = .{ .mesh = mesh, .material = material },
            .collider = .{ .shape = mesh_shapes.mesh_shape },
        },
    );

    _ = try outside.nodes.addNode(
        null,
        transform,
        .{
            .static_mesh = .{ .mesh = mesh, .material = material },
            .collider = .{ .shape = mesh_shapes.convex_shape },
        },
    );
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
