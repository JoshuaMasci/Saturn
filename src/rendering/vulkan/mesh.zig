const std = @import("std");

const vk = @import("vulkan");

const MeshAsset = @import("../../asset/mesh.zig");

const Device = @import("device.zig");
const Buffer = @import("buffer.zig");

const Self = @This();

allocator: std.mem.Allocator,
backend: *Device,
sphere_pos_radius: [4]f32,

vertex_buffer: Device.BufferHandle,
index_buffer: Device.BufferHandle,
primitives: []MeshAsset.Primitive,

meshlet_buffer: Device.BufferHandle,
meshlet_vertices_buffer: Device.BufferHandle,
meshlet_triangles_buffer: Device.BufferHandle,

pub fn init(allocator: std.mem.Allocator, backend: *Device, mesh: *const MeshAsset) !Self {
    const primitives = try allocator.dupe(MeshAsset.Primitive, mesh.primitives);
    errdefer allocator.free(primitives);

    const vertex_buffer = try backend.createBufferWithData(.{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(mesh.vertices));
    errdefer backend.destroyBuffer(vertex_buffer);

    const index_buffer = try backend.createBufferWithData(.{ .index_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(mesh.indices));
    errdefer backend.destroyBuffer(index_buffer);

    const meshlet_buffer = try backend.createBufferWithData(.{ .storage_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(mesh.meshlets));
    errdefer backend.destroyBuffer(meshlet_buffer);

    const meshlet_vertices_buffer = try backend.createBufferWithData(.{ .storage_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(mesh.meshlet_vertices));
    errdefer backend.destroyBuffer(meshlet_vertices_buffer);

    const meshlet_triangles_buffer = try backend.createBufferWithData(.{ .storage_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(mesh.meshlet_triangles));
    errdefer backend.destroyBuffer(meshlet_triangles_buffer);

    return .{
        .allocator = allocator,
        .backend = backend,
        .sphere_pos_radius = mesh.sphere_pos_radius,

        .primitives = primitives,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,

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

    self.allocator.free(self.primitives);
}
