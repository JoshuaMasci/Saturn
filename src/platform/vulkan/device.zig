const std = @import("std");

const vk = @import("vulkan");

const saturn = @import("../../root.zig");

const Instance = @import("instance.zig");
const PhysicalDevice = Instance.PhysicalDevice;

const GpuAllocator = @import("gpu_allocator.zig");
const Queue = @import("queue.zig");
const BindlessDescriptor = @import("bindless_descriptor.zig");

const Self = @This();

allocator: std.mem.Allocator,

base: vk.BaseWrapper,
instance: vk.InstanceProxy,
proxy: vk.DeviceProxy,
gpu_allocator: GpuAllocator,
descriptor: BindlessDescriptor,

physical_device: PhysicalDevice,
graphics_queue: Queue, //Pretty much every device has a graphics queue (Graphics + Compute + Transfer)
async_compute_queue: ?Queue,
async_transfer_queue: ?Queue,
extensions: saturn.DeviceFeatures,

debug: bool = false,

all_stage_flags: vk.ShaderStageFlags,

pub fn init(
    allocator: std.mem.Allocator,
    instance: *Instance,
    physical_device: PhysicalDevice,
    features: saturn.DeviceFeatures,
    debug: bool,
) !Self {
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

    if (features.mesh_shading) {
        std.debug.assert(physical_device.info.extensions.mesh_shading);
        try device_extentions.append(allocator, "VK_EXT_mesh_shader");
        all_stage_flags.task_bit_ext = true;
        all_stage_flags.mesh_bit_ext = true;
    }

    if (features.ray_tracing) {
        std.debug.assert(physical_device.info.extensions.ray_tracing);
        try device_extentions.append(allocator, "VK_KHR_deferred_host_operations");
        try device_extentions.append(allocator, "VK_KHR_acceleration_structure");
        try device_extentions.append(allocator, "VK_KHR_ray_query");
        // Not needed since VK_KHR_ray_tracing_pipeline, isn't being used
        // all_stage_flags.raygen_bit_khr = true;
        // all_stage_flags.miss_bit_khr = true;
        // all_stage_flags.closest_hit_bit_khr = true;
        // all_stage_flags.callable_bit_khr = true;
    }

    if (features.host_image_copy) {
        std.debug.assert(physical_device.info.extensions.host_image_copy);
        try device_extentions.append(allocator, "VK_EXT_host_image_copy");
    }

    var features_1 = vk.PhysicalDeviceFeatures{
        .robust_buffer_access = .true,
        .fill_mode_non_solid = .true,
        .multi_draw_indirect = .true,
    };

    var features_host_image_copy = vk.PhysicalDeviceHostImageCopyFeaturesEXT{
        .host_image_copy = .true,
    };

    var feature_mesh_shading = vk.PhysicalDeviceMeshShaderFeaturesEXT{
        .mesh_shader = .true,
        .task_shader = .true,
    };

    var features_12 = vk.PhysicalDeviceVulkan12Features{
        .buffer_device_address = if (features.buffer_device_address) .true else .false,
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

        .draw_indirect_count = .true,
        //.scalar_block_layout = .true,
    };

    var features_13 = vk.PhysicalDeviceVulkan13Features{
        .dynamic_rendering = .true,
        .synchronization_2 = .true,

        //Required for hlsl shaders
        .shader_demote_to_helper_invocation = .true,
        .shader_terminate_invocation = .true,
    };

    var features_robustness2 = vk.PhysicalDeviceRobustness2FeaturesEXT{
        .null_descriptor = .true,
        .robust_buffer_access_2 = .true,
        .robust_image_access_2 = .true,
    };

    var create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = queue_info_count,
        .p_queue_create_infos = &queue_info,
        .pp_enabled_extension_names = @ptrCast(device_extentions.items),
        .enabled_extension_count = @intCast(device_extentions.items.len),
        .p_enabled_features = &features_1,
    };

    if (physical_device.info.extensions.mesh_shading) {
        appendNextPtrChain(&create_info, &feature_mesh_shading);
    }

    if (features.host_image_copy) {
        appendNextPtrChain(&create_info, &features_host_image_copy);
    }

    appendNextPtrChain(&create_info, &features_robustness2);
    appendNextPtrChain(&create_info, &features_13);
    appendNextPtrChain(&create_info, &features_12);

    const device_handle = try instance.proxy.createDevice(
        physical_device.handle,
        &create_info,
        null,
    );

    const device_wrapper = try allocator.create(vk.DeviceWrapper);
    errdefer allocator.destroy(device_wrapper);
    device_wrapper.* = vk.DeviceWrapper.load(device_handle, instance.proxy.wrapper.dispatch.vkGetDeviceProcAddr.?);

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

    var gpu_allocator: GpuAllocator = try .init(physical_device.handle, instance.proxy, proxy, instance.base.dispatch.vkGetInstanceProcAddr.?, instance.proxy.wrapper.dispatch.vkGetDeviceProcAddr.?);
    errdefer gpu_allocator.deinit();

    return .{
        .allocator = allocator,
        .base = instance.base,
        .instance = instance.proxy,
        .physical_device = physical_device,
        .proxy = proxy,
        .gpu_allocator = gpu_allocator,
        .descriptor = try .init(allocator, proxy, .{
            .uniform_buffers = 1024,
            .storage_buffers = 1024,
            .sampled_images = 1024,
            .storage_images = 1024,
        }, all_stage_flags),

        .graphics_queue = graphics_queue,
        .async_compute_queue = async_compute_queue,
        .async_transfer_queue = async_transfer_queue,
        .extensions = features,
        .debug = debug,

        .all_stage_flags = all_stage_flags,
    };
}

pub fn deinit(self: *Self) void {
    self.descriptor.deinit();

    self.gpu_allocator.deinit();

    self.graphics_queue.deinit(self.proxy);
    if (self.async_compute_queue) |queue| queue.deinit(self.proxy);
    if (self.async_transfer_queue) |queue| queue.deinit(self.proxy);

    self.proxy.destroyDevice(null);
    self.allocator.destroy(self.proxy.wrapper);
}

pub fn setDebugName(self: Self, object_type: vk.ObjectType, handle: anytype, name: []const u8) void {
    if (!self.debug or name.len == 0) {
        return;
    }

    const c_name = self.allocator.dupeZ(u8, name) catch |err| {
        std.log.err("Failed to alloc c string for setDebugUtilsObjectNameEXT {}", .{err});
        return;
    };
    defer self.allocator.free(c_name);

    const object_handle: u64 = @intFromEnum(handle);

    self.proxy.setDebugUtilsObjectNameEXT(&.{
        .object_type = object_type,
        .object_handle = object_handle,
        .p_object_name = c_name,
    }) catch |err| {
        std.log.err("Failed to set object name \"{s}\" for  {}: {}", .{ name, handle, err });
    };
}

fn appendNextPtrChain(root: anytype, next_struct: anytype) void {
    next_struct.*.p_next = @constCast(root.*.p_next); //Don't care about the const since im only modifiying the p_next field
    root.*.p_next = next_struct;
}

fn loadGlobal(self: *const @This(), name: [*c]const u8) vk.PfnVoidFunction {
    return self.base.getInstanceProcAddr(.null_handle, name);
}

fn loadInstance(self: *const @This(), name: [*c]const u8) vk.PfnVoidFunction {
    return self.base.getInstanceProcAddr(self.instance.handle, name);
}

fn loadDevice(self: *@This(), name: [*c]const u8) vk.PfnVoidFunction {
    return self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?(self.proxy.handle, name);
}

pub fn getProcAddr(function_name: [*c]const u8, user_data: ?*anyopaque) callconv(std.builtin.CallingConvention.c) vk.PfnVoidFunction {
    var self: *Self = @ptrCast(@alignCast(user_data));

    if (self.loadGlobal(function_name)) |func| return func;
    if (self.loadInstance(function_name)) |func| return func;
    if (self.loadDevice(function_name)) |func| return func;
    return null;
}
