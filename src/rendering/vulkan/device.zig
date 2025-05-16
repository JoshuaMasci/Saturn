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

pub fn render(self: Self) !void {
    const fence = try self.device.createFence(&.{}, null);
    defer self.device.destroyFence(fence, null);

    var command_buffers: [1]vk.CommandBuffer = undefined;
    try self.device.allocateCommandBuffers(&.{ .command_buffer_count = @intCast(command_buffers.len), .command_pool = self.graphics_queue.command_pool, .level = .primary }, &command_buffers);
    defer self.device.freeCommandBuffers(self.graphics_queue.command_pool, @intCast(command_buffers.len), &command_buffers);

    const command_buffer = command_buffers[0];

    try self.device.beginCommandBuffer(command_buffer, &.{});
    try self.device.endCommandBuffer(command_buffer);

    const submit_infos: [1]vk.SubmitInfo = .{.{
        .command_buffer_count = @intCast(command_buffers.len),
        .p_command_buffers = &command_buffers,
    }};

    try self.device.queueSubmit(self.graphics_queue.handle, @intCast(submit_infos.len), &submit_infos, fence);
    _ = try self.device.waitForFences(1, &.{fence}, 1, std.math.maxInt(u64));
}
