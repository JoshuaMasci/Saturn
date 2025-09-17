const std = @import("std");

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

pub fn generateMeshBounds(
    //comptime VertexType: type,
    // vertices: []VertexType,
    // position_offset: usize,
    postions: []const [3]f32,
) [4]f32 {
    const VertexStride: usize = @sizeOf([3]f32);
    const bounds = c.meshopt_computeSphereBounds(@ptrCast(postions.ptr), postions.len, VertexStride, null, 0);
    return .{ bounds.center[0], bounds.center[1], bounds.center[2], bounds.radius };
}

pub const Meshlet = struct {
    vertex_offset: u32,
    vertex_count: u32,
    triangle_offset: u32,
    triangle_count: u32,

    sphere_pos_radius: [4]f32,
};

pub fn generateMeshlets(
    //comptime VertexType: type,
    allocator: std.mem.Allocator,
    postions: []const [3]f32,
    indices: []const u32,
    limits: MeshletLimits,
) !struct {
    meshlets: []Meshlet,
    meshlet_vertices: []u32,
    meshlet_triangles: []u8,
} {
    const VertexStride: usize = @sizeOf([3]f32);

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
        @ptrCast(postions.ptr),
        postions.len,
        VertexStride,
        limits.max_vertices,
        limits.max_triangles,
        0.0,
    );

    const meshlets = try allocator.alloc(Meshlet, actual_count);
    errdefer allocator.free(meshlets);

    for (meshlets, meshopt_meshlets[0..actual_count]) |*dst, src| {
        // Optimize meshlets
        c.meshopt_optimizeMeshlet(&meshlet_vertices[src.vertex_offset], &meshlet_triangles[src.triangle_offset], src.triangle_count, src.vertex_count);

        // Calculate meshlets bounds
        const bounds: c.meshopt_Bounds = c.meshopt_computeMeshletBounds(
            &meshlet_vertices[src.vertex_offset],
            &meshlet_triangles[src.triangle_offset],
            src.triangle_count,
            @ptrCast(postions.ptr),
            postions.len,
            VertexStride,
        );
        dst.* = .{
            .vertex_offset = src.vertex_offset,
            .vertex_count = src.vertex_count,
            .triangle_offset = src.triangle_offset,
            .triangle_count = src.triangle_count,
            .sphere_pos_radius = .{ bounds.center[0], bounds.center[1], bounds.center[2], bounds.radius },
        };
    }

    //Shrink buffers, doesn't matter much if it fails
    const last = meshlets[meshlets.len - 1];
    meshlet_vertices = try allocator.realloc(meshlet_vertices, last.vertex_offset + last.vertex_count);
    meshlet_triangles = try allocator.realloc(meshlet_triangles, last.triangle_offset + last.triangle_count * 3);

    return .{
        .meshlets = meshlets,
        .meshlet_vertices = meshlet_vertices,
        .meshlet_triangles = meshlet_triangles,
    };
}
