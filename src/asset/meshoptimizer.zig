const std = @import("std");

const Mesh = @import("mesh.zig");

pub const c = @cImport({
    @cInclude("meshoptimizer.h");
});

pub const MeshletLimits = struct {
    /// Crossplatform recommendations from meshopt documetation
    pub const General: @This() = .{ .max_vertices = 64, .max_triangles = 96 };

    // Nvidia spesific recommendations
    pub const Nvidia: @This() = .{ .max_vertices = 64, .max_triangles = 126 };

    // AMD spesific recommendations
    pub const AMD: @This() = .{ .max_vertices = 64, .max_triangles = 64 };

    max_vertices: u32,
    max_triangles: u32,
};

pub const Settings = struct {
    meshlet_limits: MeshletLimits = .General,
};

pub const Primitive = struct {
    vertex_offset: u32,
    vertex_count: u32,
    index_offset: u32,
    index_count: u32,
};

pub fn buildMesh(
    allocator: std.mem.Allocator,
    name: []const u8,
    vertices: []Mesh.Vertex,
    indices: []Mesh.Index,
    primitives: []Primitive,
    settings: Settings,
) !Mesh {
    var mesh_vertices: std.ArrayList(Mesh.Vertex) = .empty;
    errdefer mesh_vertices.deinit(allocator);

    var mesh_indices: std.ArrayList(Mesh.Index) = .empty;
    errdefer mesh_indices.deinit(allocator);

    const mesh_primitives: []Mesh.Primitive = try allocator.alloc(Mesh.Primitive, primitives.len);
    errdefer allocator.free(mesh_primitives);

    var meshlets: std.ArrayList(Mesh.Meshlet) = .empty;
    errdefer meshlets.deinit(allocator);

    var meshlet_vertices: std.ArrayList(u32) = .empty;
    errdefer meshlet_vertices.deinit(allocator);

    var meshlet_triangles: std.ArrayList(u8) = .empty;
    errdefer meshlet_triangles.deinit(allocator);

    for (mesh_primitives, primitives) |*output, input| {
        const input_vertices = vertices[input.vertex_offset..(input.vertex_offset + input.vertex_count)];
        const input_indices = indices[input.index_offset..(input.index_offset + input.index_count)];
        output.* = try buildPrimitive(
            allocator,
            input_vertices,
            input_indices,
            &mesh_vertices,
            &mesh_indices,
            &meshlets,
            &meshlet_vertices,
            &meshlet_triangles,
            settings,
        );
    }

    return .{
        .name = try allocator.dupe(u8, name),
        .sphere_pos_radius = generateMeshBounds(Mesh.Vertex, mesh_vertices.items),

        .vertices = try mesh_vertices.toOwnedSlice(allocator),
        .indices = try mesh_indices.toOwnedSlice(allocator),
        .primitives = mesh_primitives,

        .meshlets = try meshlets.toOwnedSlice(allocator),
        .meshlet_vertices = try meshlet_vertices.toOwnedSlice(allocator),
        .meshlet_triangles = try meshlet_triangles.toOwnedSlice(allocator),
    };
}

pub fn buildPrimitive(
    allocator: std.mem.Allocator,
    vertices: []const Mesh.Vertex,
    indices: []const Mesh.Index,
    output_vertices: *std.ArrayList(Mesh.Vertex),
    output_indices: *std.ArrayList(Mesh.Index),
    output_meshlets: *std.ArrayList(Mesh.Meshlet),
    output_meshlet_vertices: *std.ArrayList(u32),
    output_meshlet_triangles: *std.ArrayList(u8),
    settings: Settings,
) !Mesh.Primitive {

    //If indices aren't provided generate basic indices to be used by meshopt
    var generated_indices: ?[]u32 = null;
    defer if (generated_indices) |temp| allocator.free(temp);

    if (indices.len == 0) {
        generated_indices = try allocator.alloc(Mesh.Index, vertices.len);
        for (generated_indices.?, 0..) |*index, i| {
            index.* = @intCast(i);
        }
    }
    const temp = if (generated_indices) |generated| generated else indices;

    const remap_list = try allocator.alloc(Mesh.Index, vertices.len);
    defer allocator.free(remap_list);

    const unique_vertex_count = c.meshopt_generateVertexRemap(remap_list.ptr, temp.ptr, temp.len, vertices.ptr, vertices.len, @sizeOf(Mesh.Vertex));

    const new_vertices = try allocator.alloc(Mesh.Vertex, unique_vertex_count);
    defer allocator.free(new_vertices);

    const new_index_count = if (indices.len != 0) indices.len else vertices.len;
    const new_indices = try allocator.alloc(Mesh.Index, new_index_count);
    defer allocator.free(new_indices);

    // Remap Passes
    c.meshopt_remapVertexBuffer(new_vertices.ptr, vertices.ptr, vertices.len, @sizeOf(Mesh.Vertex), remap_list.ptr);
    c.meshopt_remapIndexBuffer(new_indices.ptr, if (indices.len != 0) indices.ptr else remap_list.ptr, new_indices.len, remap_list.ptr);

    // Optimize Passes
    c.meshopt_optimizeVertexCache(new_indices.ptr, new_indices.ptr, new_indices.len, new_vertices.len);
    _ = c.meshopt_optimizeVertexFetch(new_vertices.ptr, new_indices.ptr, new_indices.len, new_vertices.ptr, new_vertices.len, @sizeOf(Mesh.Vertex));

    const vertex_offset: u32 = @intCast(output_vertices.items.len);
    const vertex_count: u32 = @intCast(new_vertices.len);

    const index_offset: u32 = @intCast(output_indices.items.len);
    const index_count: u32 = @intCast(new_indices.len);

    // Append to output lists
    try output_vertices.appendSlice(allocator, new_vertices);
    try output_indices.appendSlice(allocator, new_indices);

    // Genrate Meshlets
    const result = try generateMeshlets(Mesh.Vertex, allocator, new_vertices, new_indices, settings.meshlet_limits);
    defer allocator.free(result.meshlets);
    defer allocator.free(result.meshlet_vertices);
    defer allocator.free(result.meshlet_triangles);

    // Adjust meshlet offsets
    for (result.meshlets) |*meshlet| {
        meshlet.vertex_offset += @intCast(output_meshlet_vertices.items.len);
        meshlet.triangle_offset += @intCast(output_meshlet_triangles.items.len);
    }

    const meshlet_offset: u32 = @intCast(output_meshlets.items.len);
    const meshlet_count: u32 = @intCast(result.meshlets.len);

    try output_meshlets.appendSlice(allocator, result.meshlets);
    try output_meshlet_vertices.appendSlice(allocator, result.meshlet_vertices);
    try output_meshlet_triangles.appendSlice(allocator, result.meshlet_triangles);

    return .{
        .sphere_pos_radius = generateMeshBounds(Mesh.Vertex, new_vertices),

        .vertex_offset = vertex_offset,
        .vertex_count = vertex_count,

        .index_offset = index_offset,
        .index_count = index_count,

        .meshlet_offset = meshlet_offset,
        .meshlet_count = meshlet_count,
    };
}

pub fn generateMeshBounds(
    comptime VertexType: type,
    vertices: []VertexType,
) [4]f32 {
    const VertexStride: usize = @sizeOf(VertexType);
    const bounds = c.meshopt_computeSphereBounds(@ptrCast(vertices.ptr), vertices.len, VertexStride, null, 0);
    return .{ bounds.center[0], bounds.center[1], bounds.center[2], bounds.radius };
}

pub fn generateMeshlets(
    comptime VertexType: type,
    allocator: std.mem.Allocator,
    vertices: []const VertexType,
    indices: []const u32,
    limits: MeshletLimits,
) !struct {
    meshlets: []Mesh.Meshlet,
    meshlet_vertices: []u32,
    meshlet_triangles: []u8,
} {
    const VertexStride: usize = @sizeOf(VertexType);

    const meshlet_count = c.meshopt_buildMeshletsBound(indices.len, limits.max_vertices, limits.max_triangles);

    const meshopt_meshlets = try allocator.alloc(c.meshopt_Meshlet, meshlet_count);
    defer allocator.free(meshopt_meshlets);

    var meshlet_vertices = try allocator.alloc(u32, meshlet_count * limits.max_vertices); // upper bound
    errdefer allocator.free(meshlet_vertices);

    var meshlet_triangles = try allocator.alloc(u8, meshlet_count * limits.max_triangles * 3); // upper bound
    errdefer allocator.free(meshlet_triangles);

    const actual_count = c.meshopt_buildMeshlets(
        meshopt_meshlets.ptr,
        meshlet_vertices.ptr,
        meshlet_triangles.ptr,
        indices.ptr,
        indices.len,
        @ptrCast(vertices.ptr),
        vertices.len,
        VertexStride,
        limits.max_vertices,
        limits.max_triangles,
        0.0,
    );

    const meshlets = try allocator.alloc(Mesh.Meshlet, actual_count);
    errdefer allocator.free(meshlets);

    for (meshlets, meshopt_meshlets[0..actual_count]) |*dst, src| {
        // Optimize meshlets
        c.meshopt_optimizeMeshlet(&meshlet_vertices[src.vertex_offset], &meshlet_triangles[src.triangle_offset], src.triangle_count, src.vertex_count);

        // Calculate meshlets bounds
        const bounds: c.meshopt_Bounds = c.meshopt_computeMeshletBounds(
            &meshlet_vertices[src.vertex_offset],
            &meshlet_triangles[src.triangle_offset],
            src.triangle_count,
            @ptrCast(vertices.ptr),
            vertices.len,
            VertexStride,
        );
        dst.* = .{
            .sphere_pos_radius = .{ bounds.center[0], bounds.center[1], bounds.center[2], bounds.radius },
            .vertex_offset = src.vertex_offset,
            .vertex_count = src.vertex_count,
            .triangle_offset = src.triangle_offset,
            .triangle_count = src.triangle_count,
        };
    }

    // Shrink buffers
    const last = meshlets[meshlets.len - 1];
    meshlet_vertices = try allocator.realloc(meshlet_vertices, last.vertex_offset + last.vertex_count);
    meshlet_triangles = try allocator.realloc(meshlet_triangles, last.triangle_offset + last.triangle_count * 3);

    return .{
        .meshlets = meshlets,
        .meshlet_vertices = meshlet_vertices,
        .meshlet_triangles = meshlet_triangles,
    };
}
