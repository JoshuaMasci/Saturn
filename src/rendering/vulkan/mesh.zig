const std = @import("std");

const vk = @import("vulkan");

const MeshAsset = @import("../../asset/mesh.zig");

const Backend = @import("backend.zig");
const Buffer = @import("buffer.zig");

pub const GpuInfo = extern struct {
    sphere_pos_radius: [4]f32,
    vertex_index_primitive_bindings_pad1: [4]u32,
    meshlet_vertex_triangle_bindings_pad1: [4]u32,

    //sphere_pos_radius: [4]f32,
    // vertex_binding: u32,
    // index_binding: u32,
    // meshlet_binding: u32,
    // meshlet_vertices_binding: u32,
    // meshlet_triangles_binding: u32,
};

const Self = @This();

allocator: std.mem.Allocator,
backend: *Backend,
sphere_pos_radius: [4]f32,
primitives: []MeshAsset.Primitive,

vertex_buffer: Backend.BufferHandle,
index_buffer: Backend.BufferHandle,
primitive_buffer: Backend.BufferHandle,

meshlet_buffer: Backend.BufferHandle,
meshlet_vertices_buffer: Backend.BufferHandle,
meshlet_triangles_buffer: Backend.BufferHandle,

pub fn init(allocator: std.mem.Allocator, backend: *Backend, mesh: *const MeshAsset) !Self {
    var name_buffer: [256]u8 = undefined;

    const primitives = try allocator.dupe(MeshAsset.Primitive, mesh.primitives);
    errdefer allocator.free(primitives);

    const vertex_buffer = try backend.createBufferWithData(
        std.fmt.bufPrint(&name_buffer, "{s}_vertex_buffer", .{mesh.name}) catch "",
        .{ .vertex_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true },
        std.mem.sliceAsBytes(mesh.vertices),
    );
    errdefer backend.destroyBuffer(vertex_buffer);

    const index_buffer = try backend.createBufferWithData(
        std.fmt.bufPrint(&name_buffer, "{s}_index_buffer", .{mesh.name}) catch "",
        .{ .index_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true },
        std.mem.sliceAsBytes(mesh.indices),
    );
    errdefer backend.destroyBuffer(index_buffer);

    const primitive_buffer = try backend.createBufferWithData(
        std.fmt.bufPrint(&name_buffer, "{s}_primitive_buffer", .{mesh.name}) catch "",
        .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
        std.mem.sliceAsBytes(mesh.primitives),
    );
    errdefer backend.destroyBuffer(primitive_buffer);

    const meshlet_buffer = try backend.createBufferWithData(
        std.fmt.bufPrint(&name_buffer, "{s}_meshlet_buffer", .{mesh.name}) catch "",
        .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
        std.mem.sliceAsBytes(mesh.meshlets),
    );
    errdefer backend.destroyBuffer(meshlet_buffer);

    const meshlet_vertices_buffer = try backend.createBufferWithData(
        std.fmt.bufPrint(&name_buffer, "{s}_meshlet_vertices_buffer", .{mesh.name}) catch "",
        .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
        std.mem.sliceAsBytes(mesh.meshlet_vertices),
    );
    errdefer backend.destroyBuffer(meshlet_vertices_buffer);

    const meshlet_triangles_buffer = try backend.createBufferWithData(
        std.fmt.bufPrint(&name_buffer, "{s}_meshlet_triangles_buffer", .{mesh.name}) catch "",
        .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
        std.mem.sliceAsBytes(mesh.meshlet_triangles),
    );
    errdefer backend.destroyBuffer(meshlet_triangles_buffer);

    return .{
        .allocator = allocator,
        .backend = backend,
        .sphere_pos_radius = mesh.sphere_pos_radius,
        .primitives = primitives,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .primitive_buffer = primitive_buffer,

        .meshlet_buffer = meshlet_buffer,
        .meshlet_vertices_buffer = meshlet_vertices_buffer,
        .meshlet_triangles_buffer = meshlet_triangles_buffer,
    };
}

pub fn deinit(self: Self) void {
    self.backend.destroyBuffer(self.meshlet_buffer);
    self.backend.destroyBuffer(self.meshlet_vertices_buffer);
    self.backend.destroyBuffer(self.meshlet_triangles_buffer);

    self.backend.destroyBuffer(self.vertex_buffer);
    self.backend.destroyBuffer(self.index_buffer);
    self.backend.destroyBuffer(self.primitive_buffer);

    self.allocator.free(self.primitives);
}

pub fn getGpuInfo(self: Self) GpuInfo {
    return .{
        .sphere_pos_radius = self.sphere_pos_radius,
        .vertex_index_primitive_bindings_pad1 = .{
            self.backend.buffers.get(self.vertex_buffer).?.storage_binding.?.index,
            self.backend.buffers.get(self.index_buffer).?.storage_binding.?.index,
            self.backend.buffers.get(self.primitive_buffer).?.storage_binding.?.index,
            0,
        },
        .meshlet_vertex_triangle_bindings_pad1 = .{
            self.backend.buffers.get(self.meshlet_buffer).?.storage_binding.?.index,
            self.backend.buffers.get(self.meshlet_vertices_buffer).?.storage_binding.?.index,
            self.backend.buffers.get(self.meshlet_triangles_buffer).?.storage_binding.?.index,
            0,
        },
    };
}
