const std = @import("std");
const zobj = @import("zobj");
const Mesh = @import("mesh.zig");
const meshopt = @import("meshoptimizer.zig");

pub fn loadObjMesh(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !Mesh {
    const file_buffer = try dir.readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    defer allocator.free(file_buffer);

    var model = try zobj.parseObj(allocator, file_buffer);
    defer model.deinit(allocator);

    const primitives: []meshopt.Primitive = try allocator.alloc(meshopt.Primitive, model.meshes.len);
    defer allocator.free(primitives);

    var vertices: std.ArrayList(Mesh.Vertex) = .empty;
    defer vertices.deinit(allocator);

    for (primitives, model.meshes) |*primitive, obj_mesh| {
        for (obj_mesh.num_vertices) |num_vertices| {
            std.debug.assert(num_vertices == 3);
        }

        const vertex_offset: u32 = @intCast(vertices.items.len);
        const vertex_count: u32 = @intCast(obj_mesh.indices.len);

        primitive.* = .{
            .vertex_offset = vertex_offset,
            .vertex_count = vertex_count,
            .index_offset = 0,
            .index_count = 0,
        };

        try vertices.ensureTotalCapacity(allocator, vertices.items.len + vertex_count);

        for (obj_mesh.indices) |index| {
            vertices.appendAssumeCapacity(.{
                .position = try extract3f(model.vertices, index.vertex.?),
                .normal = try extract3f(model.normals, index.normal.?),
                .tangent = .{ 0, 0, 0, 1 },
                .uv0 = try extract2f(model.tex_coords, index.tex_coord.?),
                .uv1 = .{ 0, 0 },
            });
        }
    }

    return meshopt.buildMesh(allocator, "", vertices.items, &.{}, primitives, .{});
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
