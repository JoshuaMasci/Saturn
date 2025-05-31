const std = @import("std");

const vk = @import("vulkan");

const MeshAsset = @import("../../asset/mesh.zig");

const Backend = @import("backend.zig");
const Buffer = @import("buffer.zig");

pub const Primitive = struct {
    vertex_buffer: Backend.BufferHandle,
    index_buffer: ?Backend.BufferHandle,

    vertex_count: u32,
    index_count: u32,
};

const Self = @This();

allocator: std.mem.Allocator,
backend: *Backend,
primitives: []Primitive,

pub fn init(allocator: std.mem.Allocator, backend: *Backend, mesh: *const MeshAsset) !Self {
    var primitives = try allocator.alloc(Primitive, mesh.primitives.len);
    for (mesh.primitives, 0..) |primitive, i| {
        const vertex_buffer = try backend.createBufferWithData(.{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(primitive.vertices));

        var index_buffer: ?Backend.BufferHandle = null;
        if (mesh.primitives[0].indices.len != 0) {
            index_buffer = try backend.createBufferWithData(.{ .index_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(primitive.indices));
        }

        primitives[i] = .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .vertex_count = @intCast(primitive.vertices.len),
            .index_count = @intCast(primitive.indices.len),
        };
    }

    return .{
        .allocator = allocator,
        .backend = backend,
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
