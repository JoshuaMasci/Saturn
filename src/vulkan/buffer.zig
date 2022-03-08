const std = @import("std");
const vk = @import("vulkan");

const Device = @import("device.zig");
const DeviceAllocator = @import("device_allocator.zig");

pub const Description = struct {
    size: usize,
    usage: vk.BufferUsageFlags,
    memory_usage: DeviceAllocator.MemoryUsage,
};

const Self = @This();

device: *Device,
allocator: *DeviceAllocator,
description: Description,
handle: vk.Buffer,
allocation: DeviceAllocator.Allocation,

pub fn init(
    device: *Device,
    allocator: *DeviceAllocator,
    description: Description,
) !Self {
    var buffer = try device.base.createBuffer(
        device.handle,
        &.{
            .flags = .{},
            .size = description.size,
            .usage = description.usage,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
        },
        null,
    );
    var memory_requirements = device.base.getBufferMemoryRequirements(device.handle, buffer);
    var allocation = try allocator.allocate(memory_requirements, description.memory_usage);
    try device.base.bindBufferMemory(device.handle, buffer, allocation.memory, allocation.offset);

    return Self{
        .device = device,
        .allocator = allocator,
        .description = description,
        .handle = buffer,
        .allocation = allocation,
    };
}

pub fn deinit(self: Self) void {
    self.device.base.destroyBuffer(self.device.handle, self.handle, null);
    self.allocator.free(self.allocation);
}

pub fn fill(self: *Self, comptime DataType: type, data: []const DataType) !void {
    var gpu_memory = try self.device.base.mapMemory(self.device.handle, self.allocation.memory, self.allocation.offset, vk.WHOLE_SIZE, .{});
    defer self.device.base.unmapMemory(self.device.handle, self.allocation.memory);

    var gpu_slice = @ptrCast([*]DataType, @alignCast(@alignOf(DataType), gpu_memory));
    std.mem.copy(DataType, gpu_slice[0..data.len], data);
}
