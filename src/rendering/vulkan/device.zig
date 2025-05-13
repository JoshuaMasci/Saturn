const std = @import("std");

const vk = @import("vulkan");

const GpuAllocator = @import("gpu_allocator.zig");

const Self = @This();

allocator: std.mem.Allocator,

instance: vk.InstanceProxy,
device: vk.DeviceProxy,

physical_device: vk.PhysicalDevice,
graphics_queue: vk.Queue,

gpu_allocator: GpuAllocator,

pub fn init(allocator: std.mem.Allocator, instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice) !Self {
    //TODO: have physical_device pick these
    const queue_priority = [_]f32{1.0};
    const graphics_queue_index: u32 = 0;

    const queue_info = [_]vk.DeviceQueueCreateInfo{
        .{ .queue_family_index = graphics_queue_index, .queue_count = 1, .p_queue_priorities = &queue_priority },
    };

    var device_extentions = std.ArrayList([*c]const u8).init(allocator);
    defer device_extentions.deinit();
    try device_extentions.append("VK_KHR_swapchain");

    const create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = 1,
        .p_queue_create_infos = &queue_info,
        .pp_enabled_extension_names = @ptrCast(device_extentions.items),
        .enabled_extension_count = @intCast(device_extentions.items.len),
    };

    const device_handle = try instance.createDevice(
        physical_device,
        &create_info,
        null,
    );

    const device_wrapper = try allocator.create(vk.DeviceWrapper);
    errdefer allocator.destroy(device_wrapper);
    device_wrapper.* = vk.DeviceWrapper.load(device_handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

    const device = vk.DeviceProxy.init(device_handle, device_wrapper);

    const graphics_queue = device.getDeviceQueue(graphics_queue_index, 0);

    return .{
        .allocator = allocator,
        .instance = instance,
        .physical_device = physical_device,
        .device = device,
        .graphics_queue = graphics_queue,
        .gpu_allocator = GpuAllocator.init(physical_device, instance, device),
    };
}

pub fn deinit(self: Self) void {
    self.gpu_allocator.deinit();
    self.device.destroyDevice(null);
    self.allocator.destroy(self.device.wrapper);
}
