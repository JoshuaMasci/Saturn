const std = @import("std");
const zm = @import("zmath");
const zmesh = @import("zmesh");

const rendering_system = @import("rendering.zig");

const TexturedVertex = @import("platform/opengl/vertex.zig").TexturedVertex;
const Mesh = @import("platform/opengl/mesh.zig");

pub fn create_color_material(rendering_backend: *rendering_system.Backend, color: [4]f32) !rendering_system.MaterialHandle {
    return try rendering_backend.materials.insert(.{ .base_color_factor = color });
}

pub fn create_cube_mesh(
    allocator: std.mem.Allocator,
    rendering_backend: *rendering_system.Backend,
    scale: [3]f32,
) !rendering_system.StaticMeshHandle {
    zmesh.init(allocator);
    defer zmesh.deinit();

    var shape = zmesh.Shape.initCube();
    defer shape.deinit();

    shape.scale(scale[0], scale[1], scale[2]);
    shape.translate(-scale[0] / 2.0, -scale[1] / 2.0, -scale[2] / 2.0);
    shape.unweld();
    shape.computeNormals();

    return create_shape_mesh(allocator, rendering_backend, &shape);
}

pub fn create_cylinder_mesh(
    allocator: std.mem.Allocator,
    rendering_backend: *rendering_system.Backend,
    height: f32,
    radius: f32,
) !rendering_system.StaticMeshHandle {
    zmesh.init(allocator);
    defer zmesh.deinit();

    var shape = zmesh.Shape.initCylinder(32, 16);
    defer shape.deinit();

    shape.rotate(std.math.degreesToRadians(90.0), 1.0, 0.0, 0.0);
    shape.scale(radius, height, radius);
    shape.unweld();
    shape.computeNormals();

    return create_shape_mesh(allocator, rendering_backend, &shape);
}

fn create_shape_mesh(
    allocator: std.mem.Allocator,
    rendering_backend: *rendering_system.Backend,
    shape: *zmesh.Shape.Shape,
) !rendering_system.StaticMeshHandle {
    var mesh_vertices = try std.ArrayList(TexturedVertex).initCapacity(allocator, shape.positions.len);
    defer mesh_vertices.deinit();

    for (shape.positions, shape.normals.?) |position, normal| {
        mesh_vertices.appendAssumeCapacity(.{
            .position = position,
            .normal = normal,
            .tangent = .{ 0.0, 0.0, 0.0, 0.0 },
            .uv0 = .{ 0.0, 0.0 },
        });
    }

    const mesh = Mesh.init(TexturedVertex, u32, mesh_vertices.items, shape.indices);
    return rendering_backend.static_meshes.insert(mesh);
}
