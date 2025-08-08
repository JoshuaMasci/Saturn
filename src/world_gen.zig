const std = @import("std");

const physics_system = @import("physics");
const zm = @import("zmath");

const MaterialAssetHandle = @import("asset/material.zig").Registry.Handle;
const Mesh = @import("asset/mesh.zig");
const MeshAssetHandle = Mesh.Registry.Handle;
const Scene = @import("asset/scene.zig");
const DebugCameraEntitySystem = @import("entity/engine//debug_camera.zig").DebugCameraEntitySystem;
const physics = @import("entity/engine/physics.zig");
const rendering = @import("entity/engine/rendering.zig");
const Entity = @import("entity/entity.zig");
const Universe = @import("entity/universe.zig");
const World = @import("entity/world.zig");
const global = @import("global.zig");
const Transform = @import("transform.zig");

pub fn create_debug_camera(universe: *Universe, world_opt: ?World.Handle, transform: Transform) !Entity.Handle {
    var entity = universe.createEntity("Debug Camera");
    entity.transform = transform;
    //entity.systems.add(DebugCameraEntitySystem{});
    entity.systems.add(physics.PhysicsEntitySystem.init(entity.handle, .dynamic));

    entity.systems.add(@import("rendering/camera.zig").PerspectiveCamera{});
    entity.systems.add(physics.PhysicsColliderComponent{ .shape = physics_system.Shape.initSphere(0.25, 1.0, 0) });

    //entity.systems.get(DebugCameraEntitySystem).?.camera_node = root_node.handle;
    entity.systems.get(physics.PhysicsEntitySystem).?.rebuildShape(entity);

    if (world_opt) |world| {
        universe.worlds.get(world).?.addEntity(entity);
    }

    return entity.handle;
}

pub fn create_props(universe: *Universe, world_handle: World.Handle, count: usize, position: zm.Vec, scale: f32) void {
    const cube_mesh_handle = MeshAssetHandle.fromRepoPath("game:models/cube.mesh").?;
    const material_handles: []const MaterialAssetHandle = &.{
        MaterialAssetHandle.fromRepoPath("engine:materials/olive.mat").?,
        MaterialAssetHandle.fromRepoPath("engine:materials/purple.mat").?,
        MaterialAssetHandle.fromRepoPath("engine:materials/teal.mat").?,
    };

    const cube_shape = physics_system.Shape.initBox(.{ scale, scale, scale }, 1, 0);

    for (0..count) |i| {
        var cube_entity = universe.createEntity("Cube Entity");
        cube_entity.transform.position = position;
        cube_entity.transform.scale = zm.splat(zm.Vec, scale);
        cube_entity.systems.add(rendering.StaticMeshComponent{ .mesh = cube_mesh_handle, .materials = rendering.MaterialArray.fromSlice(&.{material_handles[@mod(i, material_handles.len)]}) });
        cube_entity.systems.add(physics.PhysicsColliderComponent{ .shape = cube_shape });
        cube_entity.systems.add(physics.PhysicsEntitySystem.init(cube_entity.handle, .dynamic));
        cube_entity.systems.get(physics.PhysicsEntitySystem).?.rebuildShape(cube_entity);
        universe.worlds.get(world_handle).?.addEntity(cube_entity);
    }
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

    var ship_inside = universe.createEntity("Ship Inside Root");
    ship_inside.systems.add(physics.PhysicsEntitySystem.init(ship_inside.handle, .static));

    var ship_outside = universe.createEntity("Ship Outside Root");
    ship_outside.systems.add(physics.PhysicsEntitySystem.init(ship_outside.handle, .dynamic));

    const bridge_mesh_handle = MeshAssetHandle.fromRepoPath("game:models/bridge.mesh").?;
    _ = bridge_mesh_handle; // autofix
    const bridge_glass_mesh_handle = MeshAssetHandle.fromRepoPath("game:models/bridge_glass.mesh").?;
    _ = bridge_glass_mesh_handle; // autofix
    const hull_mesh_handle = MeshAssetHandle.fromRepoPath("game:models/hull.mesh").?;
    const l_hull_mesh_handle = MeshAssetHandle.fromRepoPath("game:models/l_hull.mesh").?;
    const engine_mesh_handle = MeshAssetHandle.fromRepoPath("game:models/engine.mesh").?;
    const airlock_mesh_handle = MeshAssetHandle.fromRepoPath("game:models/airlock2.mesh").?;
    const airlock_inside_mesh_handle = MeshAssetHandle.fromRepoPath("game:models/airlock2_inside.mesh").?;

    const grid_material_handle = MaterialAssetHandle.fromRepoPath("game:materials/grid.mat").?;
    const uv_grid_material_handle = MaterialAssetHandle.fromRepoPath("game:materials/uv_grid.mat").?;

    //createMeshEntity(allocator, universe, ship_inside, ship_outside, bridge_mesh_handle, grid_material_handle, .{}, false);
    //createMeshEntity(allocator, universe, ship_inside, ship_outside, bridge_glass_mesh_handle, grid_material_handle, .{}, false);
    createMeshEntity(allocator, universe, ship_inside, ship_outside, hull_mesh_handle, grid_material_handle, .{ .position = zm.f32x4(0.0, 0.0, -5.0, 0.0) }, false);
    createMeshEntity(allocator, universe, ship_inside, ship_outside, l_hull_mesh_handle, grid_material_handle, .{ .position = zm.f32x4(0.0, 0.0, -15.0, 0.0) }, false);
    createMeshEntity(allocator, universe, ship_inside, ship_outside, engine_mesh_handle, grid_material_handle, .{ .position = zm.f32x4(0.0, 0.0, -20.0, 0.0) }, false);

    createMeshEntity(allocator, universe, ship_inside, ship_outside, airlock_mesh_handle, grid_material_handle, .{ .position = zm.f32x4(5.0, 0.0, -15.0, 0.0), .rotation = zm.quatFromRollPitchYaw(0.0, std.math.pi / 2.0, 0.0) }, true);
    createMeshEntity(allocator, universe, ship_inside, ship_outside, airlock_inside_mesh_handle, uv_grid_material_handle, .{ .position = zm.f32x4(2.5 + 1.25, 0.0, -15.0, 0.0), .rotation = zm.quatFromRollPitchYaw(0.0, std.math.pi / 2.0, 0.0) }, true);

    // Airlocks
    {
        const center_transform: Transform = .{ .position = zm.f32x4(2.5 * 1.5, 0.0, -15.0, 0.0) };

        var inside_airlock_center = universe.createEntity("Airlock Inside");
        inside_airlock_center.transform = center_transform;

        var outside_airlock_center = universe.createEntity("Airlock Outside");
        outside_airlock_center.transform = center_transform;
        const airlock_volume = try PhysicsMeshes.fromHandle(allocator, airlock_inside_mesh_handle, false);

        inside_airlock_center.systems.add(@import("game/airlock.zig").AirLockComponent{ .cast_layer = 1, .cast_shape = airlock_volume.convex_shape, .linked_entity = outside_airlock_center.handle });
        outside_airlock_center.systems.add(@import("game/airlock.zig").AirLockComponent{ .cast_layer = 1, .cast_shape = airlock_volume.convex_shape, .linked_entity = inside_airlock_center.handle });

        const mesh = MeshAssetHandle.fromRepoPath("game:models/cube.mesh").?;
        const material = MaterialAssetHandle.fromRepoPath("engine:materials/teal.mat").?;
        const size = zm.f32x4(0.2, 1.0, 1.0, 0.0);
        const door_box = physics_system.Shape.initBox(zm.vecToArr3(size), 1.0, 0);

        var inside_door = universe.createEntity("Airlock Door Inside");
        inside_door.transform = .{ .position = zm.f32x4(2.5 * 0.5, 0.0, 0.0, 0.0), .scale = size };

        var outside_door = universe.createEntity("Airlock Door Outside");
        outside_door.transform = .{ .position = zm.f32x4(-2.5 * 0.5, 0.0, 0.0, 0.0), .scale = size };

        inside_door.systems.add(rendering.StaticMeshComponent{ .mesh = mesh, .materials = rendering.MaterialArray.fromSlice(&.{material}) });
        inside_door.systems.add(physics.PhysicsColliderComponent{ .shape = door_box });
        inside_door.systems.add(@import("game/button.zig").ButtonComponent{ .target = inside_airlock_center.handle });

        outside_door.systems.add(rendering.StaticMeshComponent{ .mesh = mesh, .materials = rendering.MaterialArray.fromSlice(&.{material}) });
        outside_door.systems.add(physics.PhysicsColliderComponent{ .shape = door_box });
        outside_door.systems.add(@import("game/button.zig").ButtonComponent{ .target = outside_airlock_center.handle });

        inside_airlock_center.addChild(inside_door);
        outside_airlock_center.addChild(outside_door);

        ship_inside.addChild(inside_airlock_center);
        ship_outside.addChild(outside_airlock_center);
    }

    ship_inside.systems.get(physics.PhysicsEntitySystem).?.rebuildShape(ship_inside);
    ship_outside.systems.get(physics.PhysicsEntitySystem).?.rebuildShape(ship_outside);

    ship_outside.transform.position = zm.splat(zm.Vec, 100.0);
    ship_outside.transform.rotation = zm.quatFromRollPitchYaw(0.0, std.math.pi, 0.0);

    //inside_world.addEntity(ship_inside);
    outside_world.addEntity(ship_outside);

    return .{
        .outside = outside_world.handle,
        .inside = inside_world.handle,
    };
}

const PhysicsMeshes = struct {
    convex_shape: physics_system.Shape,
    mesh_shape: physics_system.Shape,

    fn fromHandle(allocator: std.mem.Allocator, handle: MeshAssetHandle, dynamic_mesh_shape: bool) !@This() {
        var mesh = try global.assets.meshes.loadAsset(allocator, handle);
        defer mesh.deinit(allocator);

        // Converts mesh to physics formats, since they no longer match
        var physics_mesh = try PhysicsMesh.fromMesh(allocator, mesh);
        defer physics_mesh.deinit(allocator);

        var convex_shape = physics_system.Shape.initConvexHull(physics_mesh.positions, 1.0, 0);

        const mesh_shape = if (dynamic_mesh_shape)
            physics_system.Shape.initMeshWithMass(physics_mesh.positions, physics_mesh.indices, convex_shape.getMassProperties(), 0)
        else
            physics_system.Shape.initMeshStatic(physics_mesh.positions, physics_mesh.indices, 0);

        return .{
            .convex_shape = convex_shape,
            .mesh_shape = mesh_shape,
        };
    }
};

//TODO: save seprate physics meshes as asset?
pub const PhysicsMesh = struct {
    positions: [][3]f32,
    indices: []u32,

    pub fn fromMesh(allocator: std.mem.Allocator, mesh: Mesh) !@This() {
        var pos_count: usize = 0;
        var index_count: usize = 0;
        for (mesh.primitives) |prim| {
            pos_count += prim.vertices.len;
            index_count += prim.indices.len;
        }

        const positions = try allocator.alloc([3]f32, pos_count);
        errdefer allocator.free(positions);

        const indices = try allocator.alloc(u32, index_count);
        errdefer allocator.free(indices);

        var p_index: usize = 0;
        var i_index: usize = 0;
        for (mesh.primitives) |prim| {
            for (prim.vertices, 0..) |vertex, i| {
                positions[p_index + i] = vertex.position;
            }

            for (prim.indices, 0..) |idx, i| {
                indices[i_index + i] = idx + @as(u32, @intCast(p_index));
            }

            p_index += prim.vertices.len;
            i_index += prim.indices.len;
        }

        return .{
            .positions = positions,
            .indices = indices,
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.positions);
        allocator.free(self.indices);
    }
};

fn createMeshEntity(allocator: std.mem.Allocator, universe: *Universe, inside_parent: ?*Entity, outside_parent: ?*Entity, mesh: MeshAssetHandle, material: MaterialAssetHandle, transform: Transform, use_dynamic_static_mesh: bool) void {
    std.debug.assert(global.assets.meshes.isValid(mesh));
    std.debug.assert(global.assets.materials.isValid(material));
    const mesh_shapes = PhysicsMeshes.fromHandle(allocator, mesh, use_dynamic_static_mesh) catch |err| std.debug.panic("Failed to create physics meshes: {}", .{err});

    var inside = universe.createEntity("Mesh Entity Inside");
    inside.transform = transform;
    inside.systems.add(rendering.StaticMeshComponent{ .mesh = mesh, .materials = rendering.MaterialArray.fromSlice(&.{material}) });
    inside.systems.add(physics.PhysicsColliderComponent{ .shape = mesh_shapes.mesh_shape });

    const outside_shape = if (use_dynamic_static_mesh) mesh_shapes.mesh_shape else mesh_shapes.convex_shape;

    var outside = universe.createEntity("Mesh Entity Outside");
    outside.transform = transform;
    outside.systems.add(rendering.StaticMeshComponent{ .mesh = mesh, .materials = rendering.MaterialArray.fromSlice(&.{material}) });
    outside.systems.add(physics.PhysicsColliderComponent{ .shape = outside_shape });

    if (inside_parent) |inside_entity| {
        inside_entity.addChild(inside);
    }

    if (outside_parent) |outside_entity| {
        outside_entity.addChild(outside);
    }
}

pub fn loadScene(allocator: std.mem.Allocator, universe: *Universe, world_handle: World.Handle, scene_path: []const u8, root_transform: Transform) !void {
    var scene_json: std.json.Parsed(Scene) = undefined;
    {
        var file = try std.fs.cwd().openFile(scene_path, .{ .mode = .read_only });
        defer file.close();
        scene_json = try Scene.deserialzie(allocator, file.reader());
    }
    defer scene_json.deinit();
    const scene = &scene_json.value;

    var base_root = universe.createEntity("Root Entity");
    base_root.transform = root_transform;

    for (scene.root_nodes) |node_index| {
        const child = loadNode(universe, scene.nodes, node_index);
        base_root.addChild(child);
    }

    var world = universe.worlds.get(world_handle).?;
    world.addEntity(base_root);
}

fn loadNode(universe: *Universe, nodes: []const Scene.Node, node_index: usize) *Entity {
    const node = &nodes[node_index];

    var entity = universe.createEntity(node.name);
    entity.transform = node.local_transform;

    if (node.mesh) |mesh| {
        entity.systems.add(rendering.StaticMeshComponent{ .mesh = mesh.mesh, .materials = rendering.MaterialArray.fromSlice(mesh.materials) });
    }

    for (node.children) |child_index| {
        const child = loadNode(universe, nodes, child_index);
        entity.addChild(child);
    }

    return entity;
}
