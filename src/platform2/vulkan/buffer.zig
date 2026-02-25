const std = @import("std");
const vk = @import("vulkan");

const saturn = @import("../../root.zig");

const Device = @import("device.zig");
const GpuAllocator = @import("gpu_allocator.zig");
const Binding = @import("bindless_descriptor.zig").Binding;

const Self = @This();

handle: vk.Buffer,
allocation: GpuAllocator.Allocation,

size: vk.DeviceSize,
usage: saturn.BufferUsage,
memory: saturn.MemoryType,

device_address: ?vk.DeviceAddress = null,
uniform_binding: ?Binding = null,
storage_binding: ?Binding = null,

pub fn init(
    device: *Device,
    size: vk.DeviceSize,
    usage: saturn.BufferUsage,
    memory: saturn.MemoryType,
) !Self {
    const handle = try device.proxy.createBuffer(&.{
        .size = size,
        .usage = getVkUsage(usage),
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
        .flags = .{},
    }, null);
    errdefer device.proxy.destroyBuffer(handle, null);

    const mem_requirements = device.proxy.getBufferMemoryRequirements(handle);

    const allocation = try device.gpu_allocator.alloc(mem_requirements, memory);
    errdefer device.gpu_allocator.free(allocation);

    try device.proxy.bindBufferMemory(handle, allocation.memory, allocation.offset);

    var buffer: Self = .{
        .handle = handle,
        .allocation = allocation,
        .size = size,
        .usage = usage,
        .memory = memory,
    };

    if (buffer.usage.device_address) {
        buffer.device_address = device.proxy.getBufferDeviceAddress(&.{ .buffer = handle });
    }

    if (buffer.usage.uniform) {
        buffer.uniform_binding = device.descriptor.uniform_buffer_array.bind(buffer);
    }

    if (buffer.usage.storage) {
        buffer.storage_binding = device.descriptor.storage_buffer_array.bind(buffer);
    }

    return buffer;
}

pub fn deinit(self: Self, device: *Device) void {
    if (self.uniform_binding) |binding| {
        device.descriptor.uniform_buffer_array.clear(binding);
    }

    if (self.storage_binding) |binding| {
        device.descriptor.storage_buffer_array.clear(binding);
    }

    device.proxy.destroyBuffer(self.handle, null);
    device.gpu_allocator.free(self.allocation);
}

pub fn getInfo(self: *const Self) saturn.BufferInfo {
    return .{
        .size = self.size,
        .usage = self.usage,
        .memory = self.memory,
        .mapped_slice = self.allocation.getMappedByteSlice(),
        .device_address = self.device_address,
        .uniform = if (self.uniform_binding) |binding| binding.asU32() else null,
        .storage = if (self.storage_binding) |binding| binding.asU32() else null,
    };
}

pub fn getMappedSlice(self: *const Self, comptime T: type) ?[]T {
    if (self.allocation.getMappedByteSlice()) |bytes| {
        const ptr: [*]T = @ptrCast(@alignCast(bytes.ptr));
        const len = bytes.len / @sizeOf(T);
        return ptr[0..len];
    }
    return null;
}

pub fn getVkUsage(usage: saturn.BufferUsage) vk.BufferUsageFlags {
    return .{
        .vertex_buffer_bit = usage.vertex,
        .index_buffer_bit = usage.index,
        .uniform_buffer_bit = usage.uniform,
        .storage_buffer_bit = usage.storage,
        .shader_device_address_bit = usage.device_address,
        .transfer_src_bit = usage.transfer_src,
        .transfer_dst_bit = usage.transfer_dst,
    };
}
