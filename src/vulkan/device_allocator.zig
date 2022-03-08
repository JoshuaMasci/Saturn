const std = @import("std");

const vk = @import("vulkan");
const Device = @import("device.zig");

//TODO: Follow VMA new method of auto-detecting where memory should go
pub const MemoryUsage = enum {
    unknown,
    cpu_to_gpu,
    //gpu_to_cpu,
    gpu_only,
};

//TODO: have required bits + preferred bits
fn getMemoryUsageFlags(memory_usage: MemoryUsage) vk.MemoryPropertyFlags {
    return switch (memory_usage) {
        .unknown => .{},
        .cpu_to_gpu => .{ .host_visible_bit = true, .host_coherent_bit = true },
        //.gpu_to_cpu => .{ .host_visible_bit = true },
        .gpu_only => .{ .device_local_bit = true },
    };
}

pub const Allocation = struct {
    memory: vk.DeviceMemory,
    offset: vk.DeviceSize,
    size: vk.DeviceSize,
    mapped_ptr: ?*void,
};

const Self = @This();

device: *Device,
memory_properties: vk.PhysicalDeviceMemoryProperties,
allocation_count: u16 = 0,

pub fn init(device: *Device) Self {
    return Self{
        .device = device,
        .memory_properties = device.getMemoryProperties(),
    };
}

pub fn deinit(self: Self) void {
    if (self.allocation_count != 0) {
        std.log.warn("Gpu Memory Leak Detected, {} allocation(s) unfreed!", .{self.allocation_count});
    }
}

pub fn allocate(
    self: *Self,
    memory_requirements: vk.MemoryRequirements,
    memory_usage: MemoryUsage,
) !Allocation {
    self.allocation_count += 1;

    var memory = try self.device.base.allocateMemory(self.device.handle, &.{
        .allocation_size = memory_requirements.size,
        .memory_type_index = try self.findMemoryTypeIndex(memory_requirements.memory_type_bits, getMemoryUsageFlags(memory_usage)),
    }, null);

    return Allocation{
        .memory = memory,
        .offset = 0,
        .size = memory_requirements.size,
        .mapped_ptr = null,
    };
}

pub fn free(self: *Self, allocation: Allocation) void {
    self.allocation_count -= 1;

    self.device.base.freeMemory(self.device.handle, allocation.memory, null);
}

fn findMemoryTypeIndex(self: Self, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
    for (self.memory_properties.memory_types[0..self.memory_properties.memory_type_count]) |memory_type, i| {
        if (memory_type_bits & (@as(u32, 1) << @truncate(u5, i)) != 0 and memory_type.property_flags.contains(flags)) {
            return @truncate(u32, i);
        }
    }
    return error.NoSuitableMemoryType;
}
