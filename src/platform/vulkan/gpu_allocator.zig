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
    create_info: *const vk.BufferCreateInfo,
    memory: MemoryLocation,
) error{OutOfMemory}!struct {
    buffer: vk.Buffer,
    allocation: Allocation,
} {
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
        @ptrCast(create_info),
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

pub fn createTexture(
    self: *Self,
    create_info: *const vk.ImageCreateInfo,
) error{OutOfMemory}!struct {
    texture: vk.Image,
    allocation: Allocation,
} {
    var alloc_info: vma.VmaAllocationCreateInfo = .{
        .usage = vma.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
    };

    var vk_image: vma.VkImage = null;
    var vma_allocation: vma.VmaAllocation = null;

    const result = vma.vmaCreateImage(
        self.allocator,
        @ptrCast(create_info),
        &alloc_info,
        &vk_image,
        &vma_allocation,
        null,
    );

    if (result != 0) {
        return error.OutOfMemory;
    }

    return .{
        .texture = @enumFromInt(@intFromPtr(vk_image)),
        .allocation = .{
            .memory = .null_handle,
            .offset = 0,
            .size = 0,
            .location = .gpu_only,
            .mapped_ptr = null,
            .vma_allocation = vma_allocation,
        },
    };
}

pub fn destroyTexture(
    self: *Self,
    image: vk.Image,
    allocation: Allocation,
) void {
    vma.vmaDestroyImage(self.allocator, @ptrFromInt(@intFromEnum(image)), allocation.vma_allocation);
}
