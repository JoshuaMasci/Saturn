pub const std = @import("std");
const vk = @import("vulkan");

const Device = @import("vulkan/device.zig");
const RenderDevice = @import("render_device.zig").RenderDevice;

const GPU_TIMEOUT: u64 = std.math.maxInt(u64);

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    render_device: *RenderDevice,
    graphics_command_pool: vk.CommandPool,
    frame: DeviceFrame, //TODO: more than one frame in flight

    pub fn init(allocator: std.mem.Allocator, render_device: *RenderDevice) !Self {
        var graphics_command_pool = try render_device.device.base.createCommandPool(
            render_device.device.handle,
            &.{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = render_device.device.graphics_queue_index,
            },
            null,
        );

        var frame = try DeviceFrame.init(render_device.device, graphics_command_pool);

        return Self{
            .allocator = allocator,
            .render_device = render_device,
            .graphics_command_pool = graphics_command_pool,
            .frame = frame,
        };
    }

    pub fn deinit(self: *Self) void {
        self.frame.deinit();
        self.render_device.device.base.destroyCommandPool(self.render_device.device.handle, self.graphics_command_pool, null);
    }
};

fn beginSingleUseCommandBuffer(device: Device, command_pool: vk.CommandPool) !vk.CommandBuffer {
    var command_buffer: vk.CommandBuffer = undefined;
    try device.base.allocateCommandBuffers(device.handle, .{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast([*]vk.CommandBuffer, &command_buffer));
    try device.basebeginCommandBuffer(command_buffer, .{
        .flags = .{},
        .p_inheritance_info = null,
    });
    return command_buffer;
}

fn endSingleUseCommandBuffer(device: Device, queue: vk.Queue, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer) !void {
    try device.base.endCommandBuffer(command_buffer);

    const submitInfo = vk.SubmitInfo{
        .wait_semaphore_count = 0,
        .p_wait_semaphores = undefined,
        .p_wait_dst_stage_mask = undefined,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &command_buffer),
        .signal_semaphore_count = 0,
        .p_signal_semaphores = undefined,
    };
    try device.base.queueSubmit(queue, 1, @ptrCast([*]const vk.SubmitInfo, &submitInfo), vk.Fence.null_handle);
    try device.base.queueWaitIdle(queue);
    device.base.freeCommandBuffers(
        device.handle,
        command_pool,
        1,
        @ptrCast([*]const vk.CommandBuffer, &command_buffer),
    );
}

const DeviceFrame = struct {
    const Self = @This();
    device: *Device,
    frame_done_fence: vk.Fence,
    image_ready_semaphore: vk.Semaphore,
    present_semaphore: vk.Semaphore,
    command_buffer: vk.CommandBuffer,

    fn init(
        device: *Device,
        pool: vk.CommandPool,
    ) !Self {
        var frame_done_fence = try device.base.createFence(device.handle, &.{
            .flags = .{ .signaled_bit = true },
        }, null);

        var image_ready_semaphore = try device.base.createSemaphore(device.handle, &.{
            .flags = .{},
        }, null);

        var present_semaphore = try device.base.createSemaphore(device.handle, &.{
            .flags = .{},
        }, null);

        var command_buffer: vk.CommandBuffer = undefined;
        try device.base.allocateCommandBuffers(device.handle, &.{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast([*]vk.CommandBuffer, &command_buffer));

        return Self{
            .device = device,
            .frame_done_fence = frame_done_fence,
            .image_ready_semaphore = image_ready_semaphore,
            .present_semaphore = present_semaphore,
            .command_buffer = command_buffer,
        };
    }

    fn deinit(self: Self) void {
        self.device.base.destroyFence(self.device.handle, self.frame_done_fence, null);
        self.device.base.destroySemaphore(self.device.handle, self.image_ready_semaphore, null);
        self.device.base.destroySemaphore(self.device.handle, self.present_semaphore, null);
    }
};
