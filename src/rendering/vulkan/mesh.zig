const std = @import("std");

const vk = @import("vulkan");

const MeshAsset = @import("../../asset/mesh.zig");

const Device = @import("device.zig");
const Buffer = @import("buffer.zig");

pub const Primitive = struct {
    vertex_buffer: Buffer,
    index_buffer: ?Buffer,

    vertex_count: u32,
    index_count: u32,
};

const Self = @This();

allocator: std.mem.Allocator,
primitives: []Primitive,

pub fn init(allocator: std.mem.Allocator, device: *Device, mesh: *const MeshAsset) !Self {
    var primitives = try allocator.alloc(Primitive, mesh.primitives.len);
    for (mesh.primitives, 0..) |primitive, i| {
        const vertex_buffer = try createBufferFromSlice(device, MeshAsset.Vertex, primitive.vertices, .{ .vertex_buffer_bit = true });

        var index_buffer: ?Buffer = null;
        if (mesh.primitives[0].indices.len != 0) {
            index_buffer = try createBufferFromSlice(device, u32, primitive.indices, .{ .index_buffer_bit = true });
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
        .primitives = primitives,
    };
}

pub fn deinit(self: Self) void {
    for (self.primitives) |primitive| {
        primitive.vertex_buffer.deinit();
        if (primitive.index_buffer) |buffer| {
            buffer.deinit();
        }
    }
    self.allocator.free(self.primitives);
}

//TODO: don't upload during creation
fn createBufferFromSlice(device: *Device, comptime T: type, slice: []const T, usage: vk.BufferUsageFlags) !Buffer {
    const buffer_size: u32 = @intCast(slice.len * @sizeOf(T));

    //TODO: support not mapped memory
    const buffer = try Buffer.init(device, @intCast(buffer_size), usage, .gpu_mappable);

    const buffer_ptr = buffer.allocation.mapped_ptr.?;
    const buffer_slice_ptr: [*]T = @ptrCast(@alignCast(buffer_ptr));
    const buffer_slice: []T = buffer_slice_ptr[0..slice.len];

    @memcpy(buffer_slice, slice);

    return buffer;
}
