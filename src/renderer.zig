pub const std = @import("std");
const vk = @import("vulkan");

const Device = @import("vulkan/device.zig");
const RenderDevice = @import("render_device.zig").RenderDevice;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;

const GPU_TIMEOUT: u64 = std.math.maxInt(u64);

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    render_device: *RenderDevice,
    graphics_command_pool: vk.CommandPool,
    frame: DeviceFrame, //TODO: more than one frame in flight
    swapchain: Swapchain,

    pub fn init(allocator: std.mem.Allocator, render_device: *RenderDevice, surface: vk.SurfaceKHR) !Self {
        var graphics_command_pool = try render_device.device.base.createCommandPool(
            render_device.device.handle,
            &.{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = render_device.device.graphics_queue_index,
            },
            null,
        );

        var frame = try DeviceFrame.init(render_device.device, graphics_command_pool);

        var swapchain = try Swapchain.init(allocator, render_device.device, surface);

        return Self{
            .allocator = allocator,
            .render_device = render_device,
            .graphics_command_pool = graphics_command_pool,
            .frame = frame,
            .swapchain = swapchain,
        };
    }

    pub fn deinit(self: *Self) void {
        self.swapchain.deinit();
        self.frame.deinit();
        self.render_device.device.base.destroyCommandPool(self.render_device.device.handle, self.graphics_command_pool, null);
    }

    pub fn render(self: *Self) !void {
        var current_frame = &self.frame;

        var fences = [_]vk.Fence{current_frame.frame_done_fence};
        _ = try self.render_device.device.base.waitForFences(self.render_device.device.handle, fences.len, &fences, 1, GPU_TIMEOUT);

        var swapchain_index = self.swapchain.getNextImage(current_frame.image_ready_semaphore) orelse return; //Swapchain invalid don't render this frame
        _ = swapchain_index;

        _ = self.render_device.device.base.resetFences(self.render_device.device.handle, fences.len, &fences) catch {};

        try self.render_device.device.base.beginCommandBuffer(current_frame.graphics_command_buffer, &.{
            .flags = .{},
            .p_inheritance_info = null,
        });

        var image_barrier = vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{},
            .old_layout = .@"undefined",
            .new_layout = .present_src_khr,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.swapchain.images.items[swapchain_index],
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };
        var empty_memory: [*]const vk.MemoryBarrier = undefined;
        var empty_buffer: [*]const vk.BufferMemoryBarrier = undefined;
        self.render_device.device.base.cmdPipelineBarrier(current_frame.graphics_command_buffer, .{ .top_of_pipe_bit = true }, .{ .bottom_of_pipe_bit = true }, .{}, 0, empty_memory, 0, empty_buffer, 1, @ptrCast([*]const vk.ImageMemoryBarrier, &image_barrier));

        try self.render_device.device.base.endCommandBuffer(current_frame.graphics_command_buffer);

        {
            var wait_semaphores = [_]vk.Semaphore{current_frame.image_ready_semaphore};
            var wait_stages = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};
            var command_buffers = [_]vk.CommandBuffer{current_frame.graphics_command_buffer};
            var signal_semaphores = [_]vk.Semaphore{current_frame.render_done_semaphore};

            const submit_infos = [_]vk.SubmitInfo{.{
                .wait_semaphore_count = wait_semaphores.len,
                .p_wait_semaphores = &wait_semaphores,
                .p_wait_dst_stage_mask = &wait_stages,
                .command_buffer_count = command_buffers.len,
                .p_command_buffers = &command_buffers,
                .signal_semaphore_count = signal_semaphores.len,
                .p_signal_semaphores = &signal_semaphores,
            }};
            try self.render_device.device.base.queueSubmit(self.render_device.device.graphics_queue, submit_infos.len, &submit_infos, current_frame.frame_done_fence);
        }

        {
            var wait_semaphores = [_]vk.Semaphore{current_frame.render_done_semaphore};
            var swapchains = [_]vk.SwapchainKHR{self.swapchain.handle};
            var image_indices = [_]u32{swapchain_index};

            _ = self.render_device.device.base.queuePresentKHR(self.render_device.device.graphics_queue, &.{
                .wait_semaphore_count = wait_semaphores.len,
                .p_wait_semaphores = &wait_semaphores,
                .swapchain_count = swapchains.len,
                .p_swapchains = &swapchains,
                .p_image_indices = &image_indices,
                .p_results = null,
            }) catch |err| {
                switch (err) {
                    error.OutOfDateKHR => {
                        self.swapchain.invalid = true;
                    },
                    else => return err,
                }
            };
        }
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
    transfer_done_semaphore: vk.Semaphore,
    render_done_semaphore: vk.Semaphore,

    transfer_command_buffer: vk.CommandBuffer,
    graphics_command_buffer: vk.CommandBuffer,

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

        var transfer_done_semaphore = try device.base.createSemaphore(device.handle, &.{
            .flags = .{},
        }, null);

        var render_done_semaphore = try device.base.createSemaphore(device.handle, &.{
            .flags = .{},
        }, null);

        var command_buffers: [2]vk.CommandBuffer = undefined;
        try device.base.allocateCommandBuffers(device.handle, &.{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = command_buffers.len,
        }, &command_buffers);

        return Self{
            .device = device,
            .frame_done_fence = frame_done_fence,
            .image_ready_semaphore = image_ready_semaphore,
            .transfer_done_semaphore = transfer_done_semaphore,
            .render_done_semaphore = render_done_semaphore,
            .transfer_command_buffer = command_buffers[0],
            .graphics_command_buffer = command_buffers[1],
        };
    }

    fn deinit(self: Self) void {
        self.device.base.destroyFence(self.device.handle, self.frame_done_fence, null);
        self.device.base.destroySemaphore(self.device.handle, self.image_ready_semaphore, null);
        self.device.base.destroySemaphore(self.device.handle, self.transfer_done_semaphore, null);
        self.device.base.destroySemaphore(self.device.handle, self.render_done_semaphore, null);
    }
};
