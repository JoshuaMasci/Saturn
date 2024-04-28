const std = @import("std");
const zmesh = @import("zmesh");

const renderer = @import("renderer/renderer.zig");

const TexturedVertex = @import("renderer/opengl/vertex.zig").TexturedVertex;

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

    var mesh_vertices = std.ArrayList(TexturedVertex).init(allocator);
    defer mesh_vertices.deinit();

    return renderer_ref.load_static_mesh(file_path);
}
