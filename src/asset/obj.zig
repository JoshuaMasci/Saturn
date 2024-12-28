const std = @import("std");
const zobj = @import("zobj");
const Mesh = @import("mesh.zig");

pub fn loadObjMesh(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !Mesh {
    const file_buffer = try dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
    defer allocator.free(file_buffer);

    var model = try zobj.parseObj(allocator, file_buffer);
    defer model.deinit(allocator);

    const primitive_count = model.meshes.len;
    var index_count: usize = 0;
    for (model.meshes) |obj_mesh| {
        index_count += obj_mesh.indices.len;
    }

    const primitives = try allocator.alloc(Mesh.Primitive, primitive_count);
    errdefer allocator.free(primitives);

    const positions = try allocator.alloc(Mesh.VertexPositions, index_count);
    errdefer allocator.free(positions);

    const attributes = try allocator.alloc(Mesh.VertexAttributes, index_count);
    errdefer allocator.free(attributes);

    const mesh: Mesh = .{
        .name = &.{},
        .primitives = primitives,
        .positions = positions,
        .attributes = attributes,
        .indices = &.{},
    };

    var global_index: u32 = 0;
    for (model.meshes, 0..) |obj_mesh, primitive_index| {
        for (obj_mesh.num_vertices) |num_vertices| {
            std.debug.assert(num_vertices == 3);
        }

        mesh.primitives[primitive_index] = .{
            .index_offset = global_index,
            .index_count = @intCast(obj_mesh.indices.len),
        };
        for (obj_mesh.indices) |index| {
            mesh.positions[global_index] = try extract3f(model.vertices, index.vertex.?);
            mesh.attributes[global_index] = .{
                .normal = try extract3f(model.normals, index.normal.?),
                .tangent = .{ 0.0, 0.0, 0.0, 1.0 },
                .uv0 = try extract2f(model.tex_coords, index.tex_coord.?),
            };
            global_index += 1;
        }
    }

    std.debug.assert(global_index == index_count);

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
