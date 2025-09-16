const std = @import("std");
const zobj = @import("zobj");
const Mesh = @import("mesh.zig");

pub fn loadObjMesh(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !Mesh {
    const file_buffer = try dir.readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    defer allocator.free(file_buffer);

    var model = try zobj.parseObj(allocator, file_buffer);
    defer model.deinit(allocator);

    const primitive_count = model.meshes.len;

    const primitives = try allocator.alloc(Mesh.Primitive, primitive_count);
    errdefer allocator.free(primitives);

    for (model.meshes, 0..) |obj_mesh, primitive_index| {
        for (obj_mesh.num_vertices) |num_vertices| {
            std.debug.assert(num_vertices == 3);
        }

        const vertices = try allocator.alloc(Mesh.Vertex, obj_mesh.indices.len);
        errdefer allocator.free(vertices);

        for (obj_mesh.indices, 0..) |index, i| {
            vertices[i] = .{
                .position = try extract3f(model.vertices, index.vertex.?),
                .normal = try extract3f(model.normals, index.normal.?),
                .tangent = .{ 0, 0, 0, 1 },
                .uv0 = try extract2f(model.tex_coords, index.tex_coord.?),
                .uv1 = .{ 0, 0 },
            };
        }

        primitives[primitive_index] = .{
            .sphere_pos_radius = .{ 0, 0, 0, 0 },
            .vertices = vertices,
            .indices = &.{},
        };
    }

    var mesh: Mesh = .{
        .name = &.{},
        .sphere_pos_radius = undefined,
        .primitives = primitives,
    };
    mesh.calcBoundingSphere();

    return mesh;
}

fn extract3f(data: []const f32, idx: u32) ![3]f32 {
    const base = @as(usize, @intCast(idx)) * 3;
    if (base + 2 >= data.len) {
        return error.IndexOutOfBounds;
    }
    return [3]f32{ data[base], data[base + 1], data[base + 2] };
}

fn extract2f(data: []const f32, idx: u32) ![2]f32 {
    const base = @as(usize, @intCast(idx)) * 2;
    if (base + 1 >= data.len) {
        return error.IndexOutOfBounds;
    }
    return [2]f32{ data[base], data[base + 1] };
}
