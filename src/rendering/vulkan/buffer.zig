const std = @import("std");

const vk = @import("vulkan");

const GpuAllocator = @import("gpu_allocator.zig");
const Queue = @import("queue.zig");
const Device = @import("device.zig");
const Binding = @import("bindless_descriptor.zig").Binding;

pub const Interface = struct {
    size: usize,
    usage: vk.BufferUsageFlags,
    handle: vk.Buffer,
    uniform_binding: ?u32,
    storage_binding: ?u32,
};

const Self = @This();

device: *Device,

size: usize,
usage: vk.BufferUsageFlags,

handle: vk.Buffer,
allocation: GpuAllocator.Allocation,

uniform_binding: ?Binding = null,
storage_binding: ?Binding = null,

pub fn init(device: *Device, size: usize, usage: vk.BufferUsageFlags, memory_location: GpuAllocator.MemoryLocation) !Self {
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
        .uniform_binding = if (self.uniform_binding) |binding| binding.index else null,
        .storage_binding = if (self.storage_binding) |binding| binding.index else null,
    };
}
