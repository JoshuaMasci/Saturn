const std = @import("std");
const za = @import("zalgebra");
const rendering_system = @import("rendering.zig");
const physics_system = @import("physics");
const universe = @import("universe.zig");

const obj = @import("obj.zig");

pub fn create_ship_inside(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend) !*universe.World {
    const grid_material = try load_texture_material(rendering_backend, "res/textures/grid.png");
    const bridge_mesh = try LoadedMesh.from_obj(allocator, rendering_backend, "res/models/bridge.obj");
    const hull_mesh = try LoadedMesh.from_obj(allocator, rendering_backend, "res/models/hull.obj");
    const engine_mesh = try LoadedMesh.from_obj(allocator, rendering_backend, "res/models/engine.obj");

    var bridge_entity = universe.Entity.init(allocator, .{});
    _ = try bridge_entity.add_node(
        null,
        .{},
        .{
            .static_mesh = .{ .mesh = bridge_mesh.rendering, .material = grid_material },
            .collider = .{ .shape = bridge_mesh.physics },
        },
    );
    _ = try bridge_entity.add_node(
        null,
        .{ .position = za.Vec3.NEG_Z.scale(5.0) },
        .{
            .static_mesh = .{ .mesh = hull_mesh.rendering, .material = grid_material },
            .collider = .{ .shape = hull_mesh.physics },
        },
    );
    _ = try bridge_entity.add_node(
        null,
        .{ .position = za.Vec3.NEG_Z.scale(15.0) },
        .{
            .static_mesh = .{ .mesh = engine_mesh.rendering, .material = grid_material },
            .collider = .{ .shape = engine_mesh.physics },
        },
    );

    var world = try universe.World.init(allocator, .{ .render = universe.RenderWorldSystem.init(rendering_backend), .physics = universe.PhysicsWorldSystem.init() });
    world.add_entity(bridge_entity);
    return world;
}

const OpenglMesh = @import("platform/opengl/mesh.zig");
const TexturedVertex = @import("platform/opengl/vertex.zig").TexturedVertex;

const LoadedMesh = struct {
    rendering: rendering_system.StaticMeshHandle,
    physics: physics_system.Shape,

    fn from_obj(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend, file_path: []const u8) !@This() {
        var obj_mesh = try obj.load_obj_file(allocator, file_path);
        defer obj_mesh.deinit();

        var mesh_vertices = try std.ArrayList(TexturedVertex).initCapacity(allocator, obj_mesh.positions.items.len);
        defer mesh_vertices.deinit();

        for (obj_mesh.positions.items, obj_mesh.normals.items, obj_mesh.uv0s.items) |position, normal, uv0| {
            mesh_vertices.appendAssumeCapacity(.{
                .position = position,
                .normal = normal,
                .tangent = .{ 0.0, 0.0, 0.0, 1.0 },
                .uv0 = uv0,
            });
        }

        return .{
            .rendering = try rendering_backend.static_meshes.insert(OpenglMesh.init(TexturedVertex, u32, mesh_vertices.items, obj_mesh.indices.items)),
            .physics = physics_system.Shape.init_mesh(obj_mesh.positions.items, obj_mesh.indices.items),
        };
    }
};

const OpenglTexture = @import("platform/opengl/texture.zig");

fn load_texture_material(rendering_backend: *rendering_system.Backend, file_path: [:0]const u8) !rendering_system.MaterialHandle {
    const zstbi = @import("zstbi");

    var image = try zstbi.Image.loadFromFile(file_path, 4);
    defer image.deinit();

    const texture = try rendering_backend.load_texture(OpenglTexture.init_2d(
        .{ image.width, image.height },
        image.data,
        .{
            .load = .rgba,
            .store = .rgba,
            .layout = .u8,
            .mips = true,
        },
        .{},
    ));

    return try rendering_backend.load_material(.{
        .base_color_texture = texture,
    });
}
