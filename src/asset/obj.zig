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

    var indices: std.ArrayList(Mesh.Index) = .empty;
    defer indices.deinit(allocator);

    for (primitives, model.meshes) |*primitive, obj_mesh| {
        for (obj_mesh.num_vertices) |num_vertices| {
            std.debug.assert(num_vertices == 3);
        }

        const vertex_offset: u32 = @intCast(vertices.items.len);
        const vertex_count: u32 = @intCast(obj_mesh.indices.len);

        const index_offset: u32 = @intCast(indices.items.len);
        const index_count: u32 = vertex_count;

        primitive.* = .{
            .vertex_offset = vertex_offset,
            .vertex_count = vertex_count,
            .index_offset = index_offset,
            .index_count = index_count,
        };

        try vertices.ensureTotalCapacity(allocator, vertices.items.len + vertex_count);
        try indices.ensureTotalCapacity(allocator, vertices.capacity);

        for (obj_mesh.indices, 0..) |index, i| {
            vertices.appendAssumeCapacity(.{
                .position = extractArrayFromSlice(3, model.vertices, index.vertex.?),
                .normal = extractArrayFromSlice(3, model.normals, index.normal.?),
                .tangent = .{ 0, 0, 0, 1 },
                .uv0 = extractArrayFromSlice(2, model.tex_coords, index.tex_coord.?),
                .uv1 = .{ 0, 0 },
            });
            indices.appendAssumeCapacity(@intCast(i));
        }
    }

    return meshopt.buildMesh(allocator, "", vertices.items, indices.items, primitives, .{});
}

fn extractArrayFromSlice(comptime I: comptime_int, data: []const f32, idx: u32) [I]f32 {
    const start = @as(usize, @intCast(idx)) * I;
    const end = start + I;

    var arr: [I]f32 = undefined;
    inline for (&arr, data[start..end]) |*dst, src| {
        dst.* = src;
    }

    return arr;
}
