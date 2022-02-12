const Device = @import("vulkan/device.zig").Device;
const Buffer = @import("vulkan/buffer.zig").Buffer;

pub const Mesh = struct {
    const Self = @This();

    vertex_buffer: Buffer,
    vertex_count: u32,
    index_buffer: Buffer,
    index_count: u32,

    pub fn init(comptime VertexType: type, comptime IndexType: type, device: Device, vertex_count: u32, index_count: u32) !Self {
        var vertex_data_size = vertex_count * @intCast(u32, @sizeOf(VertexType));
        var vertex_buffer = try Buffer.init(device, vertex_data_size, .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .{ .device_local_bit = true });
        var index_data_size = index_count * @intCast(u32, @sizeOf(IndexType));
        var index_buffer = try Buffer.init(device, index_data_size, .{ .index_buffer_bit = true, .transfer_dst_bit = true }, .{ .device_local_bit = true });

        return Self{
            .vertex_buffer = vertex_buffer,
            .vertex_count = vertex_count,
            .index_buffer = index_buffer,
            .index_count = index_count,
        };
    }

    pub fn deinit(self: Self) void {
        self.vertex_buffer.deinit();
        self.index_buffer.deinit();
    }
};
