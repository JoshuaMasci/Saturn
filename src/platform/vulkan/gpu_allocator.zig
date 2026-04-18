const std = @import("std");

const vk = @import("vulkan");
const vma = @import("vma");

pub const MemoryLocation = @import("../../root.zig").MemoryLocation;

pub const Allocation = struct {
    memory: vk.DeviceMemory,
    offset: vk.DeviceSize,
    size: vk.DeviceSize,
    location: MemoryLocation,
    mapped_ptr: ?*anyopaque,

    vma_allocation: vma.VmaAllocation = null,

    pub fn getMappedByteSlice(self: *const @This()) ?[]u8 {
        if (self.mapped_ptr) |buffer_ptr| {
            const buffer_slice_ptr: [*]u8 = @ptrCast(@alignCast(buffer_ptr));
            const buffer_slice: []u8 = buffer_slice_ptr[0..self.size];
            return buffer_slice;
        } else {
            return null;
        }
    }
};

pub const Allocation2 = vma.VmaAllocation;

const Self = @This();

physical_device: vk.PhysicalDevice,
instance: vk.InstanceProxy,
device: vk.DeviceProxy,
memory_properties: vk.PhysicalDeviceMemoryProperties,

total_requested_bytes: usize = 0,

allocator: vma.VmaAllocator,

pub fn init(
    physical_device: vk.PhysicalDevice,
    instance: vk.InstanceProxy,
    device: vk.DeviceProxy,
    get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    get_device_proc_addr: vk.PfnGetDeviceProcAddr,
) !Self {
    const memory_properties = instance.getPhysicalDeviceMemoryProperties(physical_device);

    const function: vma.VmaVulkanFunctions = .{
        .vkGetInstanceProcAddr = @ptrCast(get_instance_proc_addr),
        .vkGetDeviceProcAddr = @ptrCast(get_device_proc_addr),
    };

    const create_info: vma.VmaAllocatorCreateInfo = .{
        .instance = @ptrFromInt(@intFromEnum(instance.handle)),
        .physicalDevice = @ptrFromInt(@intFromEnum(physical_device)),
        .device = @ptrFromInt(@intFromEnum(device.handle)),
        .pVulkanFunctions = &function,
        .flags = vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };

    var allocator: vma.VmaAllocator = null;

    if (vma.vmaCreateAllocator(&create_info, &allocator) != 0) {
        return error.FailedToInitVma;
    }

    return .{
        .physical_device = physical_device,
        .instance = instance,
        .device = device,
        .memory_properties = memory_properties,
        .allocator = allocator,
    };
}

pub fn deinit(self: Self) void {
    if (self.allocator) |allocator| {
        vma.vmaDestroyAllocator(allocator);
    }
}

pub fn createBuffer(
    self: *Self,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    memory: MemoryLocation,
) error{OutOfMemory}!struct {
    buffer: vk.Buffer,
    allocation: Allocation,
} {
    const create_info: vk.BufferCreateInfo = .{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    };

    var alloc_info: vma.VmaAllocationCreateInfo = switch (memory) {
        .cpu_to_gpu => .{
            .usage = vma.VMA_MEMORY_USAGE_AUTO_PREFER_HOST,
            .flags = vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        },
        .gpu_only => .{
            .usage = vma.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
        },
    };

    var vk_buffer: vma.VkBuffer = null;
    var vma_allocation: vma.VmaAllocation = null;

    var vma_allocation_info: vma.VmaAllocationInfo = .{};

    const result = vma.vmaCreateBuffer(
        self.allocator,
        @ptrCast(&create_info),
        &alloc_info,
        &vk_buffer,
        &vma_allocation,
        &vma_allocation_info,
    );

    if (result != 0) {
        return error.OutOfMemory;
    }

    return .{
        .buffer = @enumFromInt(@intFromPtr(vk_buffer)),
        .allocation = .{
            .memory = @enumFromInt(@intFromPtr(vma_allocation_info.deviceMemory)),
            .offset = vma_allocation_info.offset,
            .size = vma_allocation_info.size,
            .location = memory,
            .mapped_ptr = vma_allocation_info.pMappedData,
            .vma_allocation = vma_allocation,
        },
    };
}

pub fn destroyBuffer(
    self: *Self,
    buffer: vk.Buffer,
    allocation: Allocation,
) void {
    vma.vmaDestroyBuffer(self.allocator, @ptrFromInt(@intFromEnum(buffer)), allocation.vma_allocation);
}

pub fn alloc(
    self: *Self,
    requirements: vk.MemoryRequirements,
    location: MemoryLocation,
    device_address: bool,
) !Allocation {
    const memory_flags: vk.MemoryPropertyFlags = switch (location) {
        .cpu_to_gpu => .{ .host_visible_bit = true, .host_coherent_bit = true },
        .gpu_only => .{ .device_local_bit = true },
    };

    const memory_type_index = try self.findMemoryType(
        requirements.memory_type_bits,
        memory_flags,
    );

    var alloc_flags: vk.MemoryAllocateFlagsInfo = .{
        .device_mask = 0,
        .flags = .{ .device_address_bit = device_address },
    };

    const alloc_info = vk.MemoryAllocateInfo{
        .p_next = &alloc_flags,
        .allocation_size = requirements.size,
        .memory_type_index = memory_type_index,
    };

    const offset: vk.DeviceSize = 0;
    const memory = try self.device.allocateMemory(&alloc_info, null);

    var mapped_ptr: ?*anyopaque = null;
    if (memory_flags.contains(.{ .host_visible_bit = true, .host_coherent_bit = true })) {
        mapped_ptr = try self.device.mapMemory(memory, offset, alloc_info.allocation_size, .{});
    }

    self.total_requested_bytes += alloc_info.allocation_size;

    return .{
        .memory = memory,
        .offset = 0,
        .size = alloc_info.allocation_size,
        .location = location,
        .mapped_ptr = mapped_ptr,
    };
}

pub fn free(self: *Self, allocation: Allocation) void {
    if (allocation.mapped_ptr) |_| {
        self.device.unmapMemory(allocation.memory);
    }

    self.device.freeMemory(allocation.memory, null);

    self.total_requested_bytes -= allocation.size;
}

fn findMemoryType(self: *const Self, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
    for (self.memory_properties.memory_types[0..self.memory_properties.memory_type_count], 0..) |mem_type, i| {
        if (memory_type_bits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
            return @truncate(i);
        }
    }
    return error.NoSuitableMemoryType;
}
