const std = @import("std");
const zmesh = @import("zmesh");

const renderer = @import("renderer/renderer.zig");

const TexturedVertex = @import("renderer/opengl/vertex.zig").TexturedVertex;
const Mesh = @import("renderer/opengl/mesh.zig");

pub fn load_gltf_mesh(allocator: std.mem.Allocator, file_path: [:0]const u8, renderer_ref: *renderer.Renderer) !renderer.StaticMeshHandle {
    const start = std.time.Instant.now() catch unreachable;
    defer {
        const end = std.time.Instant.now() catch unreachable;
        const time_ns: f32 = @floatFromInt(end.since(start));
        std.log.info("{s} loading took: {d:.3}ms", .{ file_path, time_ns / std.time.ns_per_ms });
    }

    zmesh.init(allocator);
    defer zmesh.deinit();

    const data = try zmesh.io.parseAndLoadFile(file_path);
    defer zmesh.io.freeData(data);

    var mesh_indices = std.ArrayList(u32).init(allocator);
    defer mesh_indices.deinit();

    var mesh_positions = std.ArrayList([3]f32).init(allocator);
    defer mesh_positions.deinit();

    var mesh_normals = std.ArrayList([3]f32).init(allocator);
    defer mesh_normals.deinit();

    var mesh_tangents = std.ArrayList([4]f32).init(allocator);
    defer mesh_tangents.deinit();

    var mesh_uv0s = std.ArrayList([2]f32).init(allocator);
    defer mesh_uv0s.deinit();

    try zmesh.io.appendMeshPrimitive(
        data,
        0, // mesh index
        0, // gltf primitive index (submesh index)
        &mesh_indices,
        &mesh_positions,
        &mesh_normals,
        &mesh_uv0s,
        &mesh_tangents,
    );

    var mesh_vertices = try std.ArrayList(TexturedVertex).initCapacity(allocator, mesh_positions.items.len);
    defer mesh_vertices.deinit();

    for (mesh_positions.items, mesh_normals.items, mesh_tangents.items, mesh_uv0s.items) |position, normal, tangent, uv0| {
        mesh_vertices.appendAssumeCapacity(.{
            .position = position,
            .normal = normal,
            .tangent = tangent,
            .uv0 = uv0,
        });
    }

    std.log.info("{} Vertices {} Indices", .{ mesh_positions.items.len, mesh_indices.items.len });
    const mesh = Mesh.init(TexturedVertex, u32, mesh_vertices.items, mesh_indices.items);
    return try renderer_ref.static_meshes.insert(mesh);
}
