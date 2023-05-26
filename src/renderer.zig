pub const std = @import("std");
const vk = @import("vulkan");

const Device = @import("vulkan/device.zig");
const RenderDevice = @import("render_device.zig").RenderDevice;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;

const Buffer = @import("vulkan/buffer.zig");
const Image = @import("vulkan/image.zig");

const graph = @import("renderer/render_graph.zig");

const GPU_TIMEOUT: u64 = std.math.maxInt(u64);

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    render_device: *RenderDevice,
    graphics_command_pool: vk.CommandPool,
    frame: DeviceFrame, //TODO: more than one frame in flight
    swapchain: Swapchain,

    //TEMP
    swapchain_index: u32 = 0,
    render_graph_renderer: RenderGraphRenderer,

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
            .render_graph_renderer = RenderGraphRenderer.init(allocator, render_device),
        };
    }

    pub fn deinit(self: *Self) void {
        self.render_graph_renderer.deinit();
        self.swapchain.deinit();
        self.frame.deinit();
        self.render_device.device.base.destroyCommandPool(self.render_device.device.handle, self.graphics_command_pool, null);
    }

    pub fn createRenderGraph(self: *Self) !?graph.RenderGraph {
        var current_frame = &self.frame;
        var fences = [_]vk.Fence{current_frame.frame_done_fence};
        _ = try self.render_device.device.base.waitForFences(self.render_device.device.handle, fences.len, &fences, 1, GPU_TIMEOUT);
        self.swapchain_index = self.swapchain.getNextImage(current_frame.image_ready_semaphore) orelse return null; //Swapchain invalid don't render this frame
        _ = self.render_device.device.base.resetFences(self.render_device.device.handle, fences.len, &fences) catch {};

        var render_graph = graph.RenderGraph.init(self.allocator);
        render_graph.setSwapchainImage(self.swapchain.images.items[self.swapchain_index]);
        return render_graph;
    }

    pub fn sumbitRenderGraph(self: *Self, render_graph: *graph.RenderGraph) !void {
        var current_frame = &self.frame;

        //Add final present barrier
        var final_pass = render_graph.createRenderPass("PresentRenderPass");
        render_graph.addImageAccess(final_pass, render_graph.getSwapchainImage(), .present);

        try self.render_device.device.base.beginCommandBuffer(current_frame.graphics_command_buffer, &.{
            .flags = .{},
            .p_inheritance_info = null,
        });

        try self.render_graph_renderer.render(current_frame.graphics_command_buffer, render_graph);

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
            var image_indices = [_]u32{self.swapchain_index};

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

const BufferResource = struct {
    buffer: Buffer,
    last_access: graph.BufferAccess,
    temporary: bool,
};

const ImageResource = struct {
    image: Image,
    last_access: graph.ImageAccess,
    temporary: bool,
};

const RenderGraphRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    render_device: *RenderDevice,

    allocated_buffers: std.ArrayList(?BufferResource),
    allocated_images: std.ArrayList(?ImageResource),

    fn init(
        allocator: std.mem.Allocator,
        render_device: *RenderDevice,
    ) Self {
        return Self{
            .allocator = allocator,
            .render_device = render_device,
            .allocated_buffers = std.ArrayList(?BufferResource).init(allocator),
            .allocated_images = std.ArrayList(?ImageResource).init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.clearResources();

        self.allocated_buffers.deinit();
        self.allocated_images.deinit();
    }

    fn clearResources(self: *Self) void {
        for (self.allocated_buffers.items) |option| {
            if (option) |resource| {
                if (resource.temporary) {
                    resource.buffer.deinit();
                }
            }
        }

        for (self.allocated_images.items) |option| {
            if (option) |resource| {
                if (resource.temporary) {
                    resource.image.deinit();
                }
            }
        }

        self.allocated_buffers.clearRetainingCapacity();
        self.allocated_images.clearRetainingCapacity();
    }

    fn initResources(self: *Self, render_graph: *graph.RenderGraph) !void {
        self.clearResources();

        try self.allocated_buffers.resize(render_graph.buffers.items.len);
        for (render_graph.buffers.items) |buffer_info, i| {
            self.allocated_buffers.items[i] = if (buffer_info.access_count != 0) switch (buffer_info.description) {
                .new => |description| BufferResource{
                    .buffer = try self.render_device.createBuffer(description),
                    .last_access = .none,
                    .temporary = true,
                },
                .imported => |imported_buffer| BufferResource{
                    .buffer = imported_buffer.buffer,
                    .last_access = imported_buffer.last_access,
                    .temporary = false,
                },
            } else null;
        }

        try self.allocated_images.resize(render_graph.images.items.len);
        for (render_graph.images.items) |image_info, i| {
            self.allocated_images.items[i] = if (image_info.access_count != 0) switch (image_info.description) {
                .new => |description| ImageResource{
                    .image = try self.render_device.createImage(description),
                    .last_access = .none,
                    .temporary = true,
                },
                .imported => |imported_image| ImageResource{
                    .image = imported_image.image,
                    .last_access = imported_image.last_access,
                    .temporary = false,
                },
            } else null;
        }
    }

    fn writeBarriers(
        self: *Self,
        command_buffer: vk.CommandBuffer,
        buffer_accesses: *std.AutoHashMap(graph.BufferResourceHandle, graph.BufferAccess),
        image_accesses: *std.AutoHashMap(graph.ImageResourceHandle, graph.ImageAccess),
    ) !void {
        var buffer_barriers = std.ArrayList(vk.BufferMemoryBarrier2).init(self.allocator);
        defer buffer_barriers.deinit();

        var image_barriers = std.ArrayList(vk.ImageMemoryBarrier2).init(self.allocator);
        defer image_barriers.deinit();

        var buffer_iterator = buffer_accesses.iterator();
        while (buffer_iterator.next()) |access| {
            var buffer_index = access.key_ptr.*;
            var src_flags = getBufferBarrierFlags(self.allocated_buffers.items[buffer_index].?.last_access);
            var dst_flags = getBufferBarrierFlags(access.value_ptr.*);

            self.allocated_buffers.items[buffer_index].?.last_access = access.value_ptr.*;

            try buffer_barriers.append(vk.BufferMemoryBarrier2{
                .buffer = self.allocated_buffers.items[buffer_index].?.buffer.handle,
                .offset = 0,
                .size = vk.WHOLE_SIZE,

                .src_stage_mask = src_flags.stage,
                .src_access_mask = src_flags.access,
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,

                .dst_stage_mask = dst_flags.stage,
                .dst_access_mask = dst_flags.access,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            });
        }

        const image_subresource_range = vk.ImageSubresourceRange{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        };

        var image_iterator = image_accesses.iterator();
        while (image_iterator.next()) |access| {
            var image_index = access.key_ptr.*;
            var src_flags = getImageBarrierFlags(self.allocated_images.items[image_index].?.last_access);
            var dst_flags = getImageBarrierFlags(access.value_ptr.*);

            self.allocated_images.items[image_index].?.last_access = access.value_ptr.*;

            try image_barriers.append(vk.ImageMemoryBarrier2{
                .image = self.allocated_images.items[image_index].?.image.handle,
                .subresource_range = image_subresource_range,

                .src_stage_mask = src_flags.stage,
                .src_access_mask = src_flags.access,
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .old_layout = src_flags.layout,

                .dst_stage_mask = dst_flags.stage,
                .dst_access_mask = dst_flags.access,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .new_layout = dst_flags.layout,
            });
        }

        self.render_device.device.sync2.cmdPipelineBarrier2(
            command_buffer,
            &vk.DependencyInfo{
                .dependency_flags = .{},
                .memory_barrier_count = 0,
                .p_memory_barriers = undefined,
                .buffer_memory_barrier_count = @intCast(u32, buffer_barriers.items.len),
                .p_buffer_memory_barriers = buffer_barriers.items.ptr,
                .image_memory_barrier_count = @intCast(u32, image_barriers.items.len),
                .p_image_memory_barriers = image_barriers.items.ptr,
            },
        );
    }

    fn render(self: *Self, command_buffer: vk.CommandBuffer, render_graph: *graph.RenderGraph) !void {
        try self.initResources(render_graph);
        for (render_graph.passes.items) |*pass| {
            try self.writeBarriers(command_buffer, &pass.buffer_accesses, &pass.image_accesses);

            if (pass.raster_info) |raster_info| {
                var color_attachments = try self.allocator.alloc(vk.RenderingAttachmentInfo, raster_info.color_attachments.items.len);
                defer self.allocator.free(color_attachments);

                var temp_clear_color = [_]f32{ 0.0, 0.0, 0.0, 0.0 };

                for (raster_info.color_attachments.items) |attachment_handle, i| {
                    var image = self.allocated_images.items[attachment_handle].?.image;

                    //TODO: Determine load and store ops from graph
                    //TODO: clear color
                    color_attachments[i] = .{
                        .image_view = image.view,
                        .image_layout = .color_attachment_optimal,
                        .resolve_mode = .{},
                        .resolve_image_view = .null_handle,
                        .resolve_image_layout = .@"undefined",
                        .load_op = .clear,
                        .store_op = .store,
                        .clear_value = .{ .color = .{ .float_32 = temp_clear_color } },
                    };
                }

                var depth_stencil_attachment_storage: vk.RenderingAttachmentInfo = undefined;
                var depth_stencil_attachment: ?*const vk.RenderingAttachmentInfo = null;

                if (raster_info.depth_stencil_attachment) |attachment_handle| {
                    var image = self.allocated_images.items[attachment_handle].?.image;

                    depth_stencil_attachment_storage = .{
                        .image_view = image.view,
                        .image_layout = .depth_stencil_attachment_optimal,
                        .resolve_mode = .{},
                        .resolve_image_view = .null_handle,
                        .resolve_image_layout = .@"undefined",
                        .load_op = .clear,
                        .store_op = .store,
                        .clear_value = .{ .depth_stencil = .{
                            .depth = 0.0,
                            .stencil = 0,
                        } },
                    };
                    depth_stencil_attachment = &depth_stencil_attachment_storage;
                }

                var rendering_info = vk.RenderingInfo{
                    .flags = .{},
                    .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{
                        .width = raster_info.size[0],
                        .height = raster_info.size[1],
                    } },
                    .layer_count = 1,
                    .view_mask = 0,
                    .color_attachment_count = @intCast(u32, color_attachments.len),
                    .p_color_attachments = color_attachments.ptr,
                    .p_depth_attachment = depth_stencil_attachment,
                    .p_stencil_attachment = depth_stencil_attachment,
                };

                self.render_device.device.dynamic_rendering.cmdBeginRendering(command_buffer, &rendering_info);
            }

            if (pass.render_function) |*render_function| {
                render_function.ptr(&render_function.data);
            }

            if (pass.raster_info) |_| {
                self.render_device.device.dynamic_rendering.cmdEndRendering(command_buffer);
            }
        }
    }
};

const BufferBarrierflags = struct {
    stage: vk.PipelineStageFlags2,
    access: vk.AccessFlags2,
};

fn getBufferBarrierFlags(access_type: graph.BufferAccess) BufferBarrierflags {
    return switch (access_type) {
        .none => .{ .stage = .{}, .access = .{} },
        .transfer_read => .{ .stage = .{ .all_transfer_bit = true }, .access = .{ .transfer_read_bit = true } },
        .transfer_write => .{ .stage = .{ .all_transfer_bit = true }, .access = .{ .transfer_write_bit = true } },
        .shader_read => .{ .stage = .{ .all_commands_bit = true }, .access = .{ .shader_storage_read_bit = true } },
        .shader_write => .{ .stage = .{ .all_commands_bit = true }, .access = .{ .shader_storage_write_bit = true } },
        .index_buffer => .{ .stage = .{ .index_input_bit = true }, .access = .{ .index_read_bit = true } },
        .vertex_buffer => .{ .stage = .{ .vertex_input_bit = true }, .access = .{ .vertex_attribute_read_bit = true } },
    };
}

const ImageBarrierFlags = struct {
    stage: vk.PipelineStageFlags2,
    access: vk.AccessFlags2,
    layout: vk.ImageLayout,
};

fn getImageBarrierFlags(access_type: graph.ImageAccess) ImageBarrierFlags {
    return switch (access_type) {
        .none => .{ .stage = .{}, .access = .{}, .layout = .@"undefined" },
        .transfer_read => .{ .stage = .{ .all_transfer_bit = true }, .access = .{ .transfer_read_bit = true }, .layout = .transfer_src_optimal },
        .transfer_write => .{ .stage = .{ .all_transfer_bit = true }, .access = .{ .transfer_write_bit = true }, .layout = .transfer_dst_optimal },
        .color_attachment_write => .{ .stage = .{ .color_attachment_output_bit = true }, .access = .{ .color_attachment_write_bit = true }, .layout = .color_attachment_optimal },
        .depth_stencil_attachment_write => .{ .stage = .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true }, .access = .{ .depth_stencil_attachment_write_bit = true }, .layout = .depth_stencil_attachment_optimal },
        .shader_sampled_read => .{ .stage = .{ .all_commands_bit = true }, .access = .{ .shader_sampled_read_bit = true }, .layout = .shader_read_only_optimal },
        .shader_storage_read => .{ .stage = .{ .all_commands_bit = true }, .access = .{ .shader_storage_read_bit = true }, .layout = .general },
        .shader_storage_write => .{ .stage = .{ .all_commands_bit = true }, .access = .{ .shader_storage_write_bit = true }, .layout = .general },
        .present => .{ .stage = .{ .all_commands_bit = true }, .access = .{}, .layout = .present_src_khr },
    };
}
