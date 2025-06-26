const std = @import("std");

const vk = @import("vulkan");

const GpuAllocator = @import("gpu_allocator.zig");
const Queue = @import("queue.zig");

const Self = @This();

allocator: std.mem.Allocator,

instance: vk.InstanceProxy,
proxy: vk.DeviceProxy,

physical_device: vk.PhysicalDevice,
graphics_queue: Queue,

gpu_allocator: GpuAllocator,

debug: bool = false,

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

    const VK_TRUE: u32 = 1;

    var features = vk.PhysicalDeviceFeatures{
        .robust_buffer_access = VK_TRUE,
    };

    var features_12 = vk.PhysicalDeviceVulkan12Features{
        .runtime_descriptor_array = VK_TRUE,
        .descriptor_indexing = VK_TRUE,
        .descriptor_binding_uniform_buffer_update_after_bind = VK_TRUE,
        .descriptor_binding_storage_buffer_update_after_bind = VK_TRUE,
        .descriptor_binding_sampled_image_update_after_bind = VK_TRUE,
        .descriptor_binding_storage_image_update_after_bind = VK_TRUE,
        .shader_uniform_buffer_array_non_uniform_indexing = VK_TRUE,
        .shader_storage_buffer_array_non_uniform_indexing = VK_TRUE,
        .shader_sampled_image_array_non_uniform_indexing = VK_TRUE,
        .shader_storage_image_array_non_uniform_indexing = VK_TRUE,
    };
    var features_13 = vk.PhysicalDeviceVulkan13Features{
        .p_next = @ptrCast(&features_12),
        .dynamic_rendering = VK_TRUE,
        .synchronization_2 = VK_TRUE,
    };
    var features_robustness2 = vk.PhysicalDeviceRobustness2FeaturesEXT{
        .p_next = @ptrCast(&features_13),
        .null_descriptor = VK_TRUE,
        .robust_buffer_access_2 = VK_TRUE,
        .robust_image_access_2 = VK_TRUE,
    };

    const create_info: vk.DeviceCreateInfo = .{
        .p_next = @ptrCast(&features_robustness2),
        .queue_create_info_count = 1,
        .p_queue_create_infos = &queue_info,
        .pp_enabled_extension_names = @ptrCast(device_extentions.items),
        .enabled_extension_count = @intCast(device_extentions.items.len),
        .p_enabled_features = &features,
    };

    const device_handle = try instance.createDevice(
        physical_device,
        &create_info,
        null,
    );

    const device_wrapper = try allocator.create(vk.DeviceWrapper);
    errdefer allocator.destroy(device_wrapper);
    device_wrapper.* = vk.DeviceWrapper.load(device_handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

    const proxy = vk.DeviceProxy.init(device_handle, device_wrapper);

    const graphics_queue = try Queue.init(proxy, graphics_queue_index);

    return .{
        .allocator = allocator,
        .instance = instance,
        .physical_device = physical_device,
        .proxy = proxy,
        .graphics_queue = graphics_queue,
        .gpu_allocator = GpuAllocator.init(physical_device, instance, proxy),
    };
}

pub fn deinit(self: Self) void {
    self.gpu_allocator.deinit();

    self.graphics_queue.deinit(self.proxy);

    self.proxy.destroyDevice(null);
    self.allocator.destroy(self.proxy.wrapper);
}

pub fn setDebugName(self: Self, object_type: vk.ObjectType, handle: u64, name: [:0]const u8) void {
    if (!self.debug) {
        return;
    }

    self.proxy.setDebugUtilsObjectNameEXT(&.{
        .object_type = object_type,
        .object_handle = handle,
        .p_object_name = name,
    }) catch |err| {
        std.log.err("Failed to set object name \"{s}\" for  {}: {}", .{ name, handle, err });
    };
}
