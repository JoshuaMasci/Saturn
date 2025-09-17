const std = @import("std");

const vk = @import("vulkan");

const GpuAllocator = @import("gpu_allocator.zig");
const PhysicalDevice = @import("instance.zig").PhysicalDevice;
const Queue = @import("queue.zig");

const Self = @This();

allocator: std.mem.Allocator,

instance: vk.InstanceProxy,
proxy: vk.DeviceProxy,

physical_device: vk.PhysicalDevice,
graphics_queue: Queue, //Pretty much every device has a graphics queue (Graphics + Compute + Transfer)
async_compute_queue: ?Queue,
async_transfer_queue: ?Queue,

gpu_allocator: GpuAllocator,

all_stage_flags: vk.ShaderStageFlags,

debug: bool = false,

pub fn init(allocator: std.mem.Allocator, instance: vk.InstanceProxy, physical_device: PhysicalDevice) !Self {
    if (physical_device.info.queues.graphics == null) {
        return error.NoGraphicsQueue;
    }

    const queue_priority = [_]f32{1.0};
    var queue_info_count: u32 = 0;
    var queue_info: [3]vk.DeviceQueueCreateInfo = undefined;

    if (physical_device.info.queues.graphics) |queue| {
        queue_info[queue_info_count] = .{ .queue_family_index = queue, .queue_count = 1, .p_queue_priorities = &queue_priority };
        queue_info_count += 1;
    }

    if (physical_device.info.queues.async_compute) |queue| {
        queue_info[queue_info_count] = .{ .queue_family_index = queue, .queue_count = 1, .p_queue_priorities = &queue_priority };
        queue_info_count += 1;
    }

    if (physical_device.info.queues.async_transfer) |queue| {
        queue_info[queue_info_count] = .{ .queue_family_index = queue, .queue_count = 1, .p_queue_priorities = &queue_priority };
        queue_info_count += 1;
    }

    var all_stage_flags = vk.ShaderStageFlags{
        .vertex_bit = true,
        .fragment_bit = true,
        .compute_bit = true,
    };

    var device_extentions: std.ArrayList([*c]const u8) = .empty;
    defer device_extentions.deinit(allocator);
    try device_extentions.append(allocator, "VK_KHR_swapchain");

    if (physical_device.info.extensions.mesh_shader_support) {
        try device_extentions.append(allocator, "VK_EXT_mesh_shader");
        all_stage_flags.task_bit_ext = true;
        all_stage_flags.mesh_bit_ext = true;
    }

    if (physical_device.info.extensions.raytracing_support) {
        try device_extentions.append(allocator, "VK_KHR_deferred_host_operations");
        try device_extentions.append(allocator, "VK_KHR_acceleration_structure");
        try device_extentions.append(allocator, "VK_KHR_ray_query");
        all_stage_flags.raygen_bit_khr = true;
        all_stage_flags.miss_bit_khr = true;
        all_stage_flags.closest_hit_bit_khr = true;
        all_stage_flags.callable_bit_khr = true;
    }

    //TODO: should I use the feature instead?
    if (physical_device.info.memory.direct_texture_upload) {
        try device_extentions.append(allocator, "VK_EXT_host_image_copy");
    }

    var features = vk.PhysicalDeviceFeatures{
        .robust_buffer_access = .true,
        .fill_mode_non_solid = .true,
    };

    var feature_mesh_shading = vk.PhysicalDeviceMeshShaderFeaturesEXT{
        .mesh_shader = .true,
    };

    var features_12 = vk.PhysicalDeviceVulkan12Features{
        .p_next = if (physical_device.info.extensions.mesh_shader_support) &feature_mesh_shading else null,
        .runtime_descriptor_array = .true,
        .descriptor_indexing = .true,
        .descriptor_binding_update_unused_while_pending = .true,
        .descriptor_binding_partially_bound = .true,

        .descriptor_binding_uniform_buffer_update_after_bind = .true,
        .descriptor_binding_storage_buffer_update_after_bind = .true,
        .descriptor_binding_sampled_image_update_after_bind = .true,
        .descriptor_binding_storage_image_update_after_bind = .true,

        .shader_uniform_buffer_array_non_uniform_indexing = .true,
        .shader_storage_buffer_array_non_uniform_indexing = .true,
        .shader_sampled_image_array_non_uniform_indexing = .true,
        .shader_storage_image_array_non_uniform_indexing = .true,
    };
    var features_13 = vk.PhysicalDeviceVulkan13Features{
        .p_next = @ptrCast(&features_12),
        .dynamic_rendering = .true,
        .synchronization_2 = .true,

        //Required for hlsl shaders
        .shader_demote_to_helper_invocation = .true,
        .shader_terminate_invocation = .true,
    };
    var features_robustness2 = vk.PhysicalDeviceRobustness2FeaturesEXT{
        .p_next = @ptrCast(&features_13),
        .null_descriptor = .true,
        .robust_buffer_access_2 = .true,
        .robust_image_access_2 = .true,
    };

    const create_info: vk.DeviceCreateInfo = .{
        .p_next = @ptrCast(&features_robustness2),
        .queue_create_info_count = queue_info_count,
        .p_queue_create_infos = &queue_info,
        .pp_enabled_extension_names = @ptrCast(device_extentions.items),
        .enabled_extension_count = @intCast(device_extentions.items.len),
        .p_enabled_features = &features,
    };

    const device_handle = try instance.createDevice(
        physical_device.handle,
        &create_info,
        null,
    );

    const device_wrapper = try allocator.create(vk.DeviceWrapper);
    errdefer allocator.destroy(device_wrapper);
    device_wrapper.* = vk.DeviceWrapper.load(device_handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

    const proxy = vk.DeviceProxy.init(device_handle, device_wrapper);

    const graphics_queue: Queue = try .init(proxy, physical_device.info.queues.graphics.?);
    errdefer graphics_queue.deinit(proxy);

    var async_compute_queue: ?Queue = null;
    errdefer if (async_compute_queue) |queue| queue.deinit(proxy);

    if (physical_device.info.queues.async_compute) |index| {
        async_compute_queue = try .init(proxy, index);
    }

    var async_transfer_queue: ?Queue = null;
    errdefer if (async_transfer_queue) |queue| queue.deinit(proxy);

    if (physical_device.info.queues.async_transfer) |index| {
        async_transfer_queue = try .init(proxy, index);
    }

    return .{
        .allocator = allocator,
        .instance = instance,
        .physical_device = physical_device.handle,
        .proxy = proxy,
        .graphics_queue = graphics_queue,
        .async_compute_queue = async_compute_queue,
        .async_transfer_queue = async_transfer_queue,
        .all_stage_flags = all_stage_flags,
        .gpu_allocator = GpuAllocator.init(physical_device.handle, instance, proxy),
    };
}

pub fn deinit(self: Self) void {
    self.gpu_allocator.deinit();

    self.graphics_queue.deinit(self.proxy);
    if (self.async_compute_queue) |queue| queue.deinit(self.proxy);
    if (self.async_transfer_queue) |queue| queue.deinit(self.proxy);

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
