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

    shape.translate(-0.5, -0.5, -0.5);
    shape.scale(scale[0], scale[1], scale[2]);
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

pub fn create_capsule_mesh(
    allocator: std.mem.Allocator,
    rendering_backend: *rendering_system.Backend,
    half_height: f32,
    radius: f32,
) !rendering_system.StaticMeshHandle {
    zmesh.init(allocator);
    defer zmesh.deinit();

    var base_shape = zmesh.Shape.initCylinder(32, 16);
    defer base_shape.deinit();
    base_shape.translate(0.0, 0.0, -0.5);
    base_shape.rotate(std.math.degreesToRadians(90.0), 1.0, 0.0, 0.0);
    base_shape.scale(radius, half_height * 2, radius);

    var top_sphere = zmesh.Shape.initParametricSphere(32, 32);
    defer top_sphere.deinit();
    top_sphere.scale(radius, radius, radius);
    top_sphere.rotate(std.math.degreesToRadians(90.0), 1.0, 0.0, 0.0);
    top_sphere.translate(0.0, half_height, 0.0);
    base_shape.merge(top_sphere);

    var bottom_sphere = zmesh.Shape.initParametricSphere(32, 32);
    defer bottom_sphere.deinit();
    bottom_sphere.scale(radius, radius, radius);
    bottom_sphere.rotate(std.math.degreesToRadians(90.0), 1.0, 0.0, 0.0);
    bottom_sphere.translate(0.0, -half_height, 0.0);
    base_shape.merge(bottom_sphere);

    base_shape.unweld();
    base_shape.computeNormals();

    return create_shape_mesh(allocator, rendering_backend, &base_shape);
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
