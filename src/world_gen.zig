const std = @import("std");
const global = @import("global.zig");

const za = @import("zalgebra");
const render_scene = @import("rendering/scene.zig");
const physics_system = @import("physics");
const universe = @import("universe.zig");

const obj = @import("obj.zig");
const zstbi = @import("zstbi");

const MeshAssetHandle = @import("asset/mesh.zig").Registry.Handle;

pub fn create_debug_camera(allocator: std.mem.Allocator) !universe.Entity {
    var entity = universe.Entity.init(allocator, .{});
    entity.transform.position = za.Vec3.Z.scale(10.0);
    entity.systems.debug_camera = .{};
    entity.systems.physics = universe.PhysicsEntitySystem{ .motion_type = .dynamic };
    entity.systems.debug_camera.?.camera_node = try entity.add_node(null, .{}, .{ .camera = .{}, .collider = .{ .shape = physics_system.Shape.init_sphere(0.25, 1.0) } });
    return entity;
}

pub fn create_ship_worlds(allocator: std.mem.Allocator) !struct {
    outside: *universe.World,
    inside: *universe.World,
} {
    const bridge_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/bridge.mesh").?;
    const bridge_glass_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/bridge_glass.mesh").?;
    const hull_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/hull.mesh").?;
    const engine_mesh_handle = MeshAssetHandle.fromRepoPath("engine:models/engine.mesh").?;
    const grid_material_handle = 0; //asset.MaterialAssetHandle.fromSourcePath("engine:materials/grid.mat").?;
    std.debug.assert(global.assets.meshes.isValid(bridge_mesh_handle));
    std.debug.assert(global.assets.meshes.isValid(bridge_glass_mesh_handle));
    std.debug.assert(global.assets.meshes.isValid(hull_mesh_handle));
    std.debug.assert(global.assets.meshes.isValid(engine_mesh_handle));
    //std.debug.assert(global.asset_registry.isAssetHandleValid(grid_material_handle.handle));

    const bridge_mesh = try PhysicsMeshes.fromHandle(allocator, bridge_mesh_handle);
    const bridge_glass_mesh = try PhysicsMeshes.fromHandle(allocator, bridge_glass_mesh_handle);
    const hull_mesh = try PhysicsMeshes.fromHandle(allocator, hull_mesh_handle);
    const engine_mesh = try PhysicsMeshes.fromHandle(allocator, engine_mesh_handle);

    var outside_world = try universe.World.init(allocator, .{ .render = universe.RenderWorldSystem.init(allocator), .physics = universe.PhysicsWorldSystem.init() });
    var inside_world = try universe.World.init(allocator, .{ .render = universe.RenderWorldSystem.init(allocator), .physics = universe.PhysicsWorldSystem.init() });

    //Outside
    {
        var ship_entity = universe.Entity.init(allocator, .{ .physics = .{ .motion_type = .dynamic } });
        _ = try ship_entity.add_node(
            null,
            .{},
            .{
                .static_mesh = .{ .mesh = bridge_mesh_handle, .material = grid_material_handle },
                .collider = .{ .shape = bridge_mesh.convex_shape },
            },
        );
        _ = try ship_entity.add_node(
            null,
            .{ .position = za.Vec3.NEG_Z.scale(5.0) },
            .{
                .static_mesh = .{ .mesh = hull_mesh_handle, .material = grid_material_handle },
                .collider = .{ .shape = hull_mesh.convex_shape },
            },
        );
        _ = try ship_entity.add_node(
            null,
            .{ .position = za.Vec3.NEG_Z.scale(15.0) },
            .{
                .static_mesh = .{ .mesh = engine_mesh_handle, .material = grid_material_handle },
                .collider = .{ .shape = engine_mesh.convex_shape },
            },
        );
        _ = outside_world.add_entity(ship_entity);
    }

    //Inside
    {
        var ship_entity = universe.Entity.init(allocator, .{ .physics = .{} });
        _ = try ship_entity.add_node(
            null,
            .{},
            .{
                .static_mesh = .{ .mesh = bridge_mesh_handle, .material = grid_material_handle },
                .collider = .{ .shape = bridge_mesh.mesh_shape },
            },
        );
        _ = try ship_entity.add_node(
            null,
            .{},
            .{
                //.static_mesh = .{ .mesh = bridge_glass_mesh_handle, .material = grid_material_handle },
                .collider = .{ .shape = bridge_glass_mesh.mesh_shape },
            },
        );
        _ = try ship_entity.add_node(
            null,
            .{ .position = za.Vec3.NEG_Z.scale(5.0) },
            .{
                .static_mesh = .{ .mesh = hull_mesh_handle, .material = grid_material_handle },
                .collider = .{ .shape = hull_mesh.mesh_shape },
            },
        );
        _ = try ship_entity.add_node(
            null,
            .{ .position = za.Vec3.NEG_Z.scale(15.0) },
            .{
                .static_mesh = .{ .mesh = engine_mesh_handle, .material = grid_material_handle },
                .collider = .{ .shape = engine_mesh.mesh_shape },
            },
        );
        _ = inside_world.add_entity(ship_entity);

        // {
        //     const proc = @import("procedural.zig");
        //     const materials = [_]rendering_system.MaterialHandle{
        //         try proc.create_color_material(rendering_backend, .{ 0.5, 0.0, 0.5, 1.0 }),
        //         try proc.create_color_material(rendering_backend, .{ 0.0, 0.5, 0.5, 1.0 }),
        //         try proc.create_color_material(rendering_backend, .{ 0.5, 0.5, 0.0, 1.0 }),
        //     };
        //     const cube_scale = .{0.25} ** 3;
        //     const cube_mesh = try proc.create_cube_mesh(allocator, rendering_backend, cube_scale);
        //     const cube_shape = physics_system.Shape.init_box(cube_scale, 1.0);

        //     for (0..15) |i| {
        //         const index: usize = i % materials.len;
        //         const material = materials[index];

        //         const cube_velocity = za.Vec3.NEG_Z.scale(5.0).add(za.Vec3.NEG_Y.scale(0.5));
        //         var cube_entity = universe.Entity.init(allocator, .{  .physics = .{ .motion_type = .dynamic, .linear_velocity = cube_velocity } });
        //         cube_entity.transform.position = za.Vec3.NEG_Z;
        //         _ = try cube_entity.add_node(
        //             null,
        //             .{},
        //             .{
        //                 .static_mesh = .{ .mesh = cube_mesh, .material = material },
        //                 .collider = .{ .shape = cube_shape },
        //             },
        //         );
        //         _ = inside_world.add_entity(cube_entity);
        //     }
        // }
    }

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
            .mesh_shape = physics_system.Shape.init_mesh(mesh.positions, mesh.indices),
            .convex_shape = physics_system.Shape.init_convex_hull(mesh.positions, 1.0),
        };
    }
};
