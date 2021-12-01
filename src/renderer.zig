usingnamespace @import("core.zig");

const glfw = @import("glfw");

const vk = @import("vulkan");
usingnamespace @import("vulkan/instance.zig");
usingnamespace @import("vulkan/device.zig");
usingnamespace @import("vulkan/swapchain.zig");

const TransferQueue = @import("transfer_queue.zig").TransferQueue;

const imgui = @import("Imgui.zig");
const resources = @import("resources");
const Input = @import("input.zig").Input;

const GPU_TIMEOUT: u64 = std.math.maxInt(u64);

const ColorVertex = struct {
    const Self = @This();

    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Self),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat,
            .offset = @byteOffsetOf(Self, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @byteOffsetOf(Self, "color"),
        },
    };

    pos: Vector3,
    color: Vector3,
};

pub const vertices = [_]ColorVertex{
    .{ .pos = Vector3.new(0, -0.75, 0.0), .color = Vector3.new(1, 0, 0) },
    .{ .pos = Vector3.new(-0.75, 0.75, 0.0), .color = Vector3.new(0, 1, 0) },
    .{ .pos = Vector3.new(0.75, 0.75, 0.0), .color = Vector3.new(0, 0, 1) },
};

pub const Renderer = struct {
    const Self = @This();

    allocator: *Allocator,
    instance: Instance,
    device: Device,
    surface: vk.SurfaceKHR,
    swapchain: Swapchain,
    swapchain_index: u32,

    graphics_queue: vk.Queue,
    graphics_command_pool: vk.CommandPool,

    //TODO: multiple frames in flight
    device_frame: DeviceFrame,
    transfer_queue: TransferQueue,

    images_descriptor_layout: vk.DescriptorSetLayout,
    images_descriptor_pool: vk.DescriptorPool,
    images_descriptor_set: vk.DescriptorSet,

    imgui_layer: imgui.Layer,

    pub fn init(allocator: *Allocator, window: glfw.Window) !Self {
        const vulkan_support = try glfw.vulkanSupported();
        if (!vulkan_support) {
            return error.VulkanNotSupported;
        }

        var instance = try Instance.init(allocator, "Saturn Editor", AppVersion(0, 0, 0, 0));

        var selected_device = instance.pdevices[0];
        var selected_queue_index: u32 = 0;
        var device = try Device.init(allocator, instance.dispatch, selected_device, selected_queue_index);
        var surface = try createSurface(instance.handle, window);

        var supports_surface = try instance.dispatch.getPhysicalDeviceSurfaceSupportKHR(selected_device, selected_queue_index, surface);
        if (supports_surface == 0) {
            return error.NoDeviceSurfaceSupport;
        }

        var swapchain = try Swapchain.init(allocator, instance.dispatch, device, selected_device, surface);

        var graphics_queue = device.dispatch.getDeviceQueue(device.handle, selected_queue_index, 0);
        var graphics_command_pool = try device.dispatch.createCommandPool(
            device.handle,
            .{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = selected_queue_index,
            },
            null,
        );

        const sampled_image_count: u32 = 1;
        const bindings = [_]vk.DescriptorSetLayoutBinding{.{
            .binding = 0,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = sampled_image_count,
            .stage_flags = .{ .fragment_bit = true },
            .p_immutable_samplers = null,
        }};
        const pool_sizes = [_]vk.DescriptorPoolSize{.{
            .type_ = .combined_image_sampler,
            .descriptor_count = sampled_image_count,
        }};

        var images_descriptor_layout = try device.dispatch.createDescriptorSetLayout(
            device.handle,
            .{
                .flags = .{ .update_after_bind_pool_bit = true },
                .binding_count = bindings.len,
                .p_bindings = @ptrCast([*]const vk.DescriptorSetLayoutBinding, &bindings[0]),
            },
            null,
        );

        var images_descriptor_pool = try device.dispatch.createDescriptorPool(device.handle, .{
            .flags = .{ .update_after_bind_bit = true },
            .max_sets = 1,
            .pool_size_count = pool_sizes.len,
            .p_pool_sizes = @ptrCast([*]const vk.DescriptorPoolSize, &pool_sizes[0]),
        }, null);

        var images_descriptor_set: vk.DescriptorSet = .null_handle;
        _ = try device.dispatch.allocateDescriptorSets(
            device.handle,
            .{
                .descriptor_pool = images_descriptor_pool,
                .descriptor_set_count = 1,
                .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &images_descriptor_layout),
            },
            @ptrCast([*]vk.DescriptorSet, &images_descriptor_set),
        );

        var device_frame = try DeviceFrame.init(device, graphics_command_pool);

        var transfer_queue = TransferQueue.init(allocator, device);

        var command_buffer = try beginSingleUseCommandBuffer(device, graphics_command_pool);
        try endSingleUseCommandBuffer(device, graphics_queue, graphics_command_pool, command_buffer);

        var descriptor_set_layouts = [_]vk.DescriptorSetLayout{images_descriptor_layout};
        var imgui_layer = try imgui.Layer.init(allocator, device, &transfer_queue, swapchain.render_pass, &descriptor_set_layouts);

        var image_write = vk.DescriptorImageInfo{
            .sampler = imgui_layer.texture_sampler,
            .image_view = imgui_layer.texture_atlas.image_view,
            .image_layout = .shader_read_only_optimal,
        };

        var write_descriptor_set = vk.WriteDescriptorSet{
            .dst_set = images_descriptor_set,
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .combined_image_sampler,
            .p_image_info = @ptrCast([*]vk.DescriptorImageInfo, &image_write),
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        };
        device.dispatch.updateDescriptorSets(
            device.handle,
            1,
            @ptrCast([*]vk.WriteDescriptorSet, &write_descriptor_set),
            0,
            undefined,
        );

        return Self{
            .allocator = allocator,
            .instance = instance,
            .device = device,
            .surface = surface,
            .swapchain = swapchain,
            .swapchain_index = 0,
            .graphics_queue = graphics_queue,
            .graphics_command_pool = graphics_command_pool,
            .device_frame = device_frame,
            .transfer_queue = transfer_queue,
            .images_descriptor_layout = images_descriptor_layout,
            .images_descriptor_pool = images_descriptor_pool,
            .images_descriptor_set = images_descriptor_set,
            .imgui_layer = imgui_layer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.waitIdle();
        self.device.dispatch.destroyDescriptorPool(self.device.handle, self.images_descriptor_pool, null);
        self.device.dispatch.destroyDescriptorSetLayout(self.device.handle, self.images_descriptor_layout, null);
        self.imgui_layer.deinit();
        self.transfer_queue.deinit();
        self.device_frame.deinit();
        self.swapchain.deinit();
        self.device.dispatch.destroyCommandPool(self.device.handle, self.graphics_command_pool, null);
        self.device.deinit();
        self.instance.dispatch.destroySurfaceKHR(self.instance.handle, self.surface, null);
        self.instance.deinit();
    }

    pub fn update(self: Self, window: glfw.Window, input: *Input) void {
        self.imgui_layer.update(window, input);
    }

    pub fn render(self: *Self) !void {
        var begin_result = try self.beginFrame();
        if (begin_result) |command_buffer| {
            self.imgui_layer.beginFrame();
            try self.imgui_layer.endFrame(command_buffer, &[_]vk.DescriptorSet{self.images_descriptor_set});
            try self.endFrame();
        }
    }

    fn beginFrame(self: *Self) !?vk.CommandBuffer {
        var current_frame = &self.device_frame;
        var fence = @ptrCast([*]const vk.Fence, &current_frame.frame_done_fence);
        _ = try self.device.dispatch.waitForFences(self.device.handle, 1, fence, 1, GPU_TIMEOUT);

        if (self.swapchain.getNextImage(current_frame.image_ready_semaphore)) |index| {
            self.swapchain_index = index;
        } else {
            //Swapchain invlaid don't render this frame
            return null;
        }

        _ = try self.device.dispatch.resetFences(self.device.handle, 1, fence);

        self.transfer_queue.clearResources();

        try self.device.dispatch.beginCommandBuffer(current_frame.command_buffer, .{
            .flags = .{},
            .p_inheritance_info = null,
        });

        self.transfer_queue.commitTransfers(current_frame.command_buffer);

        const extent = self.swapchain.extent;

        const clear = vk.ClearValue{
            .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
        };

        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @intToFloat(f32, extent.width),
            .height = @intToFloat(f32, extent.height),
            .min_depth = 0,
            .max_depth = 1,
        };

        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = extent,
        };

        self.device.dispatch.cmdSetViewport(current_frame.command_buffer, 0, 1, @ptrCast([*]const vk.Viewport, &viewport));
        self.device.dispatch.cmdSetScissor(current_frame.command_buffer, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor));

        self.device.dispatch.cmdBeginRenderPass(
            current_frame.command_buffer,
            .{
                .render_pass = self.swapchain.render_pass,
                .framebuffer = self.swapchain.framebuffers.items[self.swapchain_index],
                .render_area = .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = extent,
                },
                .clear_value_count = 1,
                .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear),
            },
            .@"inline",
        );

        return current_frame.command_buffer;
    }

    fn endFrame(self: *Self) !void {
        var current_frame = &self.device_frame;

        self.device.dispatch.cmdEndRenderPass(current_frame.command_buffer);

        try self.device.dispatch.endCommandBuffer(current_frame.command_buffer);

        var wait_stages = vk.PipelineStageFlags{
            .color_attachment_output_bit = true,
        };

        const submitInfo = vk.SubmitInfo{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &current_frame.image_ready_semaphore),
            .p_wait_dst_stage_mask = @ptrCast([*]const vk.PipelineStageFlags, &wait_stages),
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &current_frame.command_buffer),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast([*]const vk.Semaphore, &current_frame.present_semaphore),
        };
        try self.device.dispatch.queueSubmit(self.graphics_queue, 1, @ptrCast([*]const vk.SubmitInfo, &submitInfo), current_frame.frame_done_fence);

        _ = self.device.dispatch.queuePresentKHR(self.graphics_queue, .{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &current_frame.present_semaphore),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast([*]const vk.SwapchainKHR, &self.swapchain.handle),
            .p_image_indices = @ptrCast([*]const u32, &self.swapchain_index),
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
};

fn beginSingleUseCommandBuffer(device: Device, command_pool: vk.CommandPool) !vk.CommandBuffer {
    var command_buffer: vk.CommandBuffer = undefined;
    try device.dispatch.allocateCommandBuffers(device.handle, .{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast([*]vk.CommandBuffer, &command_buffer));
    try device.dispatch.beginCommandBuffer(command_buffer, .{
        .flags = .{},
        .p_inheritance_info = null,
    });
    return command_buffer;
}

fn endSingleUseCommandBuffer(device: Device, queue: vk.Queue, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer) !void {
    try device.dispatch.endCommandBuffer(command_buffer);

    const submitInfo = vk.SubmitInfo{
        .wait_semaphore_count = 0,
        .p_wait_semaphores = undefined,
        .p_wait_dst_stage_mask = undefined,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &command_buffer),
        .signal_semaphore_count = 0,
        .p_signal_semaphores = undefined,
    };
    try device.dispatch.queueSubmit(queue, 1, @ptrCast([*]const vk.SubmitInfo, &submitInfo), vk.Fence.null_handle);
    try device.dispatch.queueWaitIdle(queue);
    device.dispatch.freeCommandBuffers(
        device.handle,
        command_pool,
        1,
        @ptrCast([*]const vk.CommandBuffer, &command_buffer),
    );
}

fn createSurface(instance: vk.Instance, window: glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if ((try glfw.createWindowSurface(instance, window, null, &surface)) != @enumToInt(vk.Result.success)) {
        return error.SurfaceCreationFailed;
    }
    return surface;
}

const DeviceFrame = struct {
    const Self = @This();
    device: Device,
    frame_done_fence: vk.Fence,
    image_ready_semaphore: vk.Semaphore,
    present_semaphore: vk.Semaphore,
    command_buffer: vk.CommandBuffer,

    fn init(
        device: Device,
        pool: vk.CommandPool,
    ) !Self {
        var frame_done_fence = try device.dispatch.createFence(device.handle, .{
            .flags = .{ .signaled_bit = true },
        }, null);

        var image_ready_semaphore = try device.dispatch.createSemaphore(device.handle, .{
            .flags = .{},
        }, null);

        var present_semaphore = try device.dispatch.createSemaphore(device.handle, .{
            .flags = .{},
        }, null);

        var command_buffer: vk.CommandBuffer = undefined;
        try device.dispatch.allocateCommandBuffers(device.handle, .{
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
        self.device.dispatch.destroyFence(self.device.handle, self.frame_done_fence, null);
        self.device.dispatch.destroySemaphore(self.device.handle, self.image_ready_semaphore, null);
        self.device.dispatch.destroySemaphore(self.device.handle, self.present_semaphore, null);
    }
};
