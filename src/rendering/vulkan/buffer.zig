const std = @import("std");

const vk = @import("vulkan");

const Device = @import("device.zig");
const GpuAllocator = @import("gpu_allocator.zig");

const Self = @This();

device: *Device,

size: usize,
usage: vk.BufferUsageFlags,

handle: vk.Buffer,
allocation: GpuAllocator.Allocation,

pub fn init(device: *Device, size: usize, usage: vk.BufferUsageFlags, memory_location: GpuAllocator.MemoryLocation) !Self {
    const handle = try device.device.createBuffer(&.{ .size = size, .usage = usage, .sharing_mode = .exclusive }, null);
    errdefer device.device.destroyBuffer(handle, null);

    const allocation = try device.gpu_allocator.alloc(device.device.getBufferMemoryRequirements(handle), memory_location);
    errdefer device.gpu_allocator.free(allocation);
    try device.device.bindBufferMemory(handle, allocation.memory, allocation.offset);

    return .{
        .device = device,
        .size = size,
        .usage = usage,
        .handle = handle,
        .allocation = allocation,
    };
}

pub fn deinit(self: Self) void {
    self.device.device.destroyBuffer(self.handle, null);
    self.device.gpu_allocator.free(self.allocation);
}
