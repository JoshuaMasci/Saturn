const std = @import("std");

const vk = @import("vulkan");

const GpuAllocator = @import("gpu_allocator.zig");
const Queue = @import("queue.zig");
const VkDevice = @import("vulkan_device.zig");

pub const Interface = struct {
    size: usize,
    usage: vk.BufferUsageFlags,
    handle: vk.Buffer,
    uniform_binding: ?u32,
    storage_binding: ?u32,
};

const Self = @This();

device: *VkDevice,

size: usize,
usage: vk.BufferUsageFlags,

handle: vk.Buffer,
allocation: GpuAllocator.Allocation,

pub fn init(device: *VkDevice, size: usize, usage: vk.BufferUsageFlags, memory_location: GpuAllocator.MemoryLocation) !Self {
    const handle = try device.proxy.createBuffer(&.{ .size = size, .usage = usage, .sharing_mode = .exclusive }, null);
    errdefer device.proxy.destroyBuffer(handle, null);

    const allocation = try device.gpu_allocator.alloc(device.proxy.getBufferMemoryRequirements(handle), memory_location);
    errdefer device.gpu_allocator.free(allocation);
    try device.proxy.bindBufferMemory(handle, allocation.memory, allocation.offset);

    return .{
        .device = device,
        .size = size,
        .usage = usage,
        .handle = handle,
        .allocation = allocation,
    };
}

pub fn deinit(self: Self) void {
    self.device.proxy.destroyBuffer(self.handle, null);
    self.device.gpu_allocator.free(self.allocation);
}

pub fn interface(self: Self) Interface {
    return .{
        .size = self.size,
        .usage = self.usage,
        .handle = self.handle,
        .uniform_binding = null,
        .storage_binding = null,
    };
}

pub fn uploadBufferData(
    self: *Self,
    device: *VkDevice,
    queue: Queue,
    data: []const u8,
) !void {
    var command_buffers: [1]vk.CommandBuffer = undefined;
    try device.proxy.allocateCommandBuffers(&.{
        .command_pool = queue.command_pool,
        .level = vk.CommandBufferLevel.primary,
        .command_buffer_count = 1,
    }, &command_buffers);
    defer device.proxy.freeCommandBuffers(queue.command_pool, @intCast(command_buffers.len), &command_buffers);
    const command_buffer = command_buffers[0];

    const fence = try device.proxy.createFence(&.{}, null);
    defer device.proxy.destroyFence(fence, null);

    try device.proxy.beginCommandBuffer(command_buffer, &.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const Buffer = @import("buffer.zig");
    const buffer = try Buffer.init(device, data.len, .{ .transfer_src_bit = true }, .cpu_only);
    defer buffer.deinit();

    const byte_ptr: [*]u8 = @ptrCast(buffer.allocation.mapped_ptr.?);
    @memcpy(byte_ptr[0..data.len], data);

    const buffer_copy = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = data.len,
    };

    device.proxy.cmdCopyBuffer(
        command_buffer,
        buffer.handle,
        self.handle,
        1,
        (&buffer_copy)[0..1],
    );

    try device.proxy.endCommandBuffer(command_buffer);

    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = &command_buffers,
    };
    try device.proxy.queueSubmit(queue.handle, 1, (&submit_info)[0..1], fence);
    _ = try device.proxy.waitForFences(1, (&fence)[0..1], 1, std.math.maxInt(u64));
}
