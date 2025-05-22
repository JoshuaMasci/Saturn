const std = @import("std");

const vk = @import("vulkan");

const GpuAllocator = @import("gpu_allocator.zig");

const Queue = struct {
    family_index: u32,
    handle: vk.Queue,
    command_pool: vk.CommandPool,

    pub fn init(device: vk.DeviceProxy, family_index: u32) !Queue {
        return .{
            .family_index = family_index,
            .handle = device.getDeviceQueue(family_index, 0),
            .command_pool = try device.createCommandPool(&.{ .flags = .{ .reset_command_buffer_bit = true }, .queue_family_index = family_index }, null),
        };
    }

    pub fn deinit(
        self: Queue,
        device: vk.DeviceProxy,
    ) void {
        device.destroyCommandPool(self.command_pool, null);
    }
};

const Self = @This();

allocator: std.mem.Allocator,

instance: vk.InstanceProxy,
device: vk.DeviceProxy,

physical_device: vk.PhysicalDevice,
graphics_queue: Queue,

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

    const VK_TRUE: u32 = 1;

    var features = vk.PhysicalDeviceFeatures{
        .robust_buffer_access = VK_TRUE,
    };

    var features_12 = vk.PhysicalDeviceVulkan12Features{
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

    const device = vk.DeviceProxy.init(device_handle, device_wrapper);

    const graphics_queue = try Queue.init(device, graphics_queue_index);

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

    self.graphics_queue.deinit(self.device);

    self.device.destroyDevice(null);
    self.allocator.destroy(self.device.wrapper);
}

pub fn render(self: Self, swapchain: *@import("swapchain.zig"), bindless_descriptor: *@import("bindless_descriptor.zig")) !void {
    const fence = try self.device.createFence(&.{}, null);
    defer self.device.destroyFence(fence, null);

    const wait_semaphore = try self.device.createSemaphore(&.{}, null);
    defer self.device.destroySemaphore(wait_semaphore, null);

    const present_semaphore = try self.device.createSemaphore(&.{}, null);
    defer self.device.destroySemaphore(present_semaphore, null);

    var command_buffers: [1]vk.CommandBuffer = undefined;
    try self.device.allocateCommandBuffers(&.{ .command_buffer_count = @intCast(command_buffers.len), .command_pool = self.graphics_queue.command_pool, .level = .primary }, &command_buffers);
    defer self.device.freeCommandBuffers(self.graphics_queue.command_pool, @intCast(command_buffers.len), &command_buffers);

    const swapchain_image = try swapchain.acquireNextImage(null, wait_semaphore, .null_handle);

    const command_buffer_handle = command_buffers[0];
    const command_buffer = vk.CommandBufferProxy.init(command_buffer_handle, self.device.wrapper);

    try command_buffer.beginCommandBuffer(&.{});

    bindless_descriptor.bind(command_buffer);

    command_buffer.pipelineBarrier(
        .{ .all_commands_bit = true },
        .{ .all_commands_bit = true },
        .{},
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&vk.ImageMemoryBarrier{
            .image = swapchain_image.image,
            .old_layout = .undefined,
            .new_layout = .present_src_khr,
            .src_access_mask = .{},
            .dst_access_mask = .{},
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_array_layer = 0,
                .layer_count = 1,
                .base_mip_level = 0,
                .level_count = 1,
            },
        }),
    );

    try command_buffer.endCommandBuffer();

    const wait_dst_stage_mask: vk.PipelineStageFlags = .{ .all_commands_bit = true };

    const submit_infos: [1]vk.SubmitInfo = .{vk.SubmitInfo{
        .command_buffer_count = @intCast(command_buffers.len),
        .p_command_buffers = &command_buffers,
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&wait_semaphore),
        .p_wait_dst_stage_mask = @ptrCast(&wait_dst_stage_mask),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast(&present_semaphore),
    }};

    try self.device.queueSubmit(self.graphics_queue.handle, @intCast(submit_infos.len), &submit_infos, fence);

    _ = try self.device.queuePresentKHR(self.graphics_queue.handle, &.{
        .swapchain_count = 1,
        .p_image_indices = @ptrCast(&swapchain_image.index),
        .p_swapchains = @ptrCast(&swapchain_image.swapchain),
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&present_semaphore),
    });

    _ = try self.device.waitForFences(1, @ptrCast(&fence), 1, std.math.maxInt(u64));
    _ = self.device.queueWaitIdle(self.graphics_queue.handle) catch {};
}
