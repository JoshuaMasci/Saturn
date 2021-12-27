usingnamespace @import("core.zig");

const glfw = @import("glfw");

const vk = @import("vulkan");
usingnamespace @import("vulkan/instance.zig");
const Device = @import("vulkan/device.zig").Device;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;

const Mesh = @import("renderer/mesh.zig").Mesh;
const TransferQueue = @import("transfer_queue.zig").TransferQueue;
const MeshManager = @import("renderer/mesh_manager.zig").MeshManager;

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

pub const tri_vertices = [_]ColorVertex{
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

    meshes: MeshManager,

    tri_pipeline_layout: vk.PipelineLayout,
    tri_pipeline: vk.Pipeline,
    tri_mesh: Mesh,

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
                .p_bindings = &bindings,
            },
            null,
        );

        var images_descriptor_pool = try device.dispatch.createDescriptorPool(device.handle, .{
            .flags = .{ .update_after_bind_bit = true },
            .max_sets = 1,
            .pool_size_count = pool_sizes.len,
            .p_pool_sizes = &pool_sizes,
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

        var push_constant_range = vk.PushConstantRange{
            .stage_flags = .{ .vertex_bit = true },
            .offset = 0,
            .size = 64,
        };

        var tri_pipeline_layout = try device.dispatch.createPipelineLayout(device.handle, .{
            .flags = .{},
            .set_layout_count = 0,
            .p_set_layouts = undefined,
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, &push_constant_range),
        }, null);

        var tri_pipeline = try device.createPipeline(
            tri_pipeline_layout,
            swapchain.render_pass,
            &resources.tri_vert,
            &resources.tri_frag,
            &ColorVertex.binding_description,
            &ColorVertex.attribute_description,
            &.{
                .cull_mode = .{},
                .blend_enable = false,
                .src_color_blend_factor = .src_alpha,
                .dst_color_blend_factor = .one_minus_src_alpha,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .src_alpha,
                .dst_alpha_blend_factor = .one_minus_src_alpha,
                .alpha_blend_op = .add,
            },
        );

        var tri_mesh = try Mesh.init(ColorVertex, u32, device, 3, 3);
        transfer_queue.copyToBuffer(tri_mesh.vertex_buffer, ColorVertex, &tri_vertices);
        transfer_queue.copyToBuffer(tri_mesh.index_buffer, u32, &[_]u32{ 0, 1, 2 });

        var meshes = MeshManager.init(allocator, device);

        //TODO: temp call
        var mesh_id = meshes.load("assets/sphere.obj");

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
            .meshes = meshes,
            .tri_pipeline_layout = tri_pipeline_layout,
            .tri_pipeline = tri_pipeline,
            .tri_mesh = tri_mesh,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.waitIdle();

        //TODO: temp
        self.device.dispatch.destroyPipeline(self.device.handle, self.tri_pipeline, null);
        self.device.dispatch.destroyPipelineLayout(self.device.handle, self.tri_pipeline_layout, null);
        self.tri_mesh.deinit();

        self.device.dispatch.destroyDescriptorPool(self.device.handle, self.images_descriptor_pool, null);
        self.device.dispatch.destroyDescriptorSetLayout(self.device.handle, self.images_descriptor_layout, null);
        self.meshes.deinit();
        self.imgui_layer.deinit();
        self.transfer_queue.deinit();
        self.device_frame.deinit();
        self.swapchain.deinit();
        self.device.dispatch.destroyCommandPool(self.device.handle, self.graphics_command_pool, null);
        self.device.deinit();
        self.instance.dispatch.destroySurfaceKHR(self.instance.handle, self.surface, null);
        self.instance.deinit();
    }

    pub fn update(self: Self, window: glfw.Window, input: *Input, delta_time: f32) void {
        self.imgui_layer.update(window, input, delta_time);
    }

    pub fn render(self: *Self) !void {
        var begin_result = try self.beginFrame();
        if (begin_result) |command_buffer| {
            self.device.dispatch.cmdBindPipeline(command_buffer, .graphics, self.tri_pipeline);

            var size = self.swapchain.extent;

            var model = Matrix4.model(Vector3.new(0, 0, 5), Quaternion.identity, Vector3.one);
            var view = Matrix4.view_lh(Vector3.new(0, 0, -5), Quaternion.identity);
            var perspective = Matrix4.perspective_lh_zo(3.1415926 / 4.0, @intToFloat(f32, size.width) / @intToFloat(f32, size.height), 0.1, 100);
            var mvp = perspective.mul(view).mul(model);

            self.device.dispatch.cmdPushConstants(command_buffer, self.tri_pipeline_layout, .{ .vertex_bit = true }, 0, @sizeOf(Matrix4), &mvp.data);

            if (self.meshes.get(0)) |mesh| {
                self.device.dispatch.cmdBindVertexBuffers(command_buffer, 0, 1, &[_]vk.Buffer{mesh.vertex_buffer.handle}, &[_]u64{0});
                self.device.dispatch.cmdBindIndexBuffer(command_buffer, mesh.index_buffer.handle, 0, vk.IndexType.uint32);
                self.device.dispatch.cmdDrawIndexed(command_buffer, mesh.index_count, 1, 0, 0, 0);
            } else {
                self.device.dispatch.cmdBindVertexBuffers(command_buffer, 0, 1, &[_]vk.Buffer{self.tri_mesh.vertex_buffer.handle}, &[_]u64{0});
                self.device.dispatch.cmdBindIndexBuffer(command_buffer, self.tri_mesh.index_buffer.handle, 0, vk.IndexType.uint32);
                self.device.dispatch.cmdDrawIndexed(command_buffer, self.tri_mesh.index_count, 1, 0, 0, 0);
            }

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
        self.meshes.flush();

        try self.device.dispatch.beginCommandBuffer(current_frame.command_buffer, .{
            .flags = .{},
            .p_inheritance_info = null,
        });

        self.transfer_queue.commitTransfers(current_frame.command_buffer);
        self.meshes.transfers.commitTransfers(current_frame.command_buffer);

        const extent = self.swapchain.extent;

        const viewports = [_]vk.Viewport{.{
            .x = 0,
            .y = 0,
            .width = @intToFloat(f32, extent.width),
            .height = @intToFloat(f32, extent.height),
            .min_depth = 0,
            .max_depth = 1,
        }};

        const scissors = [_]vk.Rect2D{.{
            .offset = .{ .x = 0, .y = 0 },
            .extent = extent,
        }};

        self.device.dispatch.cmdSetViewport(current_frame.command_buffer, 0, 1, &viewports);
        self.device.dispatch.cmdSetScissor(current_frame.command_buffer, 0, 1, &scissors);

        const clears_values = [_]vk.ClearValue{.{
            .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
        }};

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
                .p_clear_values = &clears_values,
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

        const submit_infos = [_]vk.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &[_]vk.Semaphore{current_frame.image_ready_semaphore},
            .p_wait_dst_stage_mask = &[_]vk.PipelineStageFlags{wait_stages},
            .command_buffer_count = 1,
            .p_command_buffers = &[_]vk.CommandBuffer{current_frame.command_buffer},
            .signal_semaphore_count = 1,
            .p_signal_semaphores = &[_]vk.Semaphore{current_frame.present_semaphore},
        }};
        try self.device.dispatch.queueSubmit(self.graphics_queue, 1, &submit_infos, current_frame.frame_done_fence);

        _ = self.device.dispatch.queuePresentKHR(self.graphics_queue, .{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &[_]vk.Semaphore{current_frame.present_semaphore},
            .swapchain_count = 1,
            .p_swapchains = &[_]vk.SwapchainKHR{self.swapchain.handle},
            .p_image_indices = &[_]u32{self.swapchain_index},
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
