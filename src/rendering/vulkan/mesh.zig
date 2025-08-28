const std = @import("std");

const vk = @import("vulkan");

const MeshAsset = @import("../../asset/mesh.zig");

const Device = @import("device.zig");
const Buffer = @import("buffer.zig");

pub const Primitive = struct {
    sphere_pos_radius: [4]f32,

    vertex_buffer: Device.BufferHandle,
    index_buffer: ?Device.BufferHandle,

    vertex_count: u32,
    index_count: u32,
};

const Self = @This();

allocator: std.mem.Allocator,
backend: *Device,
sphere_pos_radius: [4]f32,
primitives: []Primitive,

pub fn init(allocator: std.mem.Allocator, backend: *Device, mesh: *const MeshAsset) !Self {
    var primitives = try allocator.alloc(Primitive, mesh.primitives.len);
    for (mesh.primitives, 0..) |primitive, i| {
        const vertex_buffer = try backend.createBufferWithData(.{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(primitive.vertices));

        var index_buffer: ?Device.BufferHandle = null;
        if (mesh.primitives[0].indices.len != 0) {
            index_buffer = try backend.createBufferWithData(.{ .index_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(primitive.indices));
        }

        primitives[i] = .{
            .sphere_pos_radius = primitive.sphere_pos_radius,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .vertex_count = @intCast(primitive.vertices.len),
            .index_count = @intCast(primitive.indices.len),
        };
    }

    return .{
        .allocator = allocator,
        .backend = backend,
        .sphere_pos_radius = mesh.sphere_pos_radius,
        .primitives = primitives,
    };
}

pub fn deinit(self: Self) void {
    for (self.primitives) |primitive| {
        self.backend.destroyBuffer(primitive.vertex_buffer);
        if (primitive.index_buffer) |buffer| {
            self.backend.destroyBuffer(buffer);
        }
    }
    self.allocator.free(self.primitives);
}
