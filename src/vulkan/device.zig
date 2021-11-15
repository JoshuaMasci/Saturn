const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vulkan");
const InstanceDispatch = @import("instance.zig").InstanceDispatch;

pub const Device = struct {
    const Self = @This();

    allocator: *Allocator,
    pdevice: vk.PhysicalDevice,
    handle: vk.Device,
    dispatch: *DeviceDispatch,
    graphics_queue: vk.Queue,
    memory_properties: vk.PhysicalDeviceMemoryProperties,

    pub fn init(
        allocator: *Allocator,
        instance_dispatch: InstanceDispatch,
        pdevice: vk.PhysicalDevice,
        graphics_queue_index: u32,
    ) !Self {
        const required_device_extensions = [_][]const u8{vk.extension_info.khr_swapchain.name};

        const props = instance_dispatch.getPhysicalDeviceProperties(pdevice);
        std.log.info("Device: \n\tName: {s}\n\tDriver: {}\n\tType: {}", .{ props.device_name, props.driver_version, props.device_type });

        const priority = [_]f32{1};
        const qci = [_]vk.DeviceQueueCreateInfo{
            .{
                .flags = .{},
                .queue_family_index = graphics_queue_index,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
        };

        var handle = try instance_dispatch.createDevice(pdevice, .{
            .flags = .{},
            .queue_create_info_count = 1,
            .p_queue_create_infos = &qci,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = required_device_extensions.len,
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, &required_device_extensions),
            .p_enabled_features = null,
        }, null);

        var dispatch: *DeviceDispatch = try allocator.create(DeviceDispatch);
        dispatch.* = try DeviceDispatch.load(handle, instance_dispatch.dispatch.vkGetDeviceProcAddr);

        var graphics_queue = dispatch.getDeviceQueue(handle, graphics_queue_index, 0);

        var memory_properties = instance_dispatch.getPhysicalDeviceMemoryProperties(pdevice);

        return Self{
            .allocator = allocator,
            .pdevice = pdevice,
            .handle = handle,
            .dispatch = dispatch,
            .graphics_queue = graphics_queue,
            .memory_properties = memory_properties,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dispatch.destroyDevice(self.handle, null);
        self.allocator.destroy(self.dispatch);
    }

    pub fn waitIdle(self: Self) void {
        self.dispatch.deviceWaitIdle(self.handle) catch panic("Failed to deviceWaitIdle", .{});
    }

    pub fn endFrame(self: *Self) !void {
        var current_frame = &self.frames[self.frame_index];

        self.dispatch.cmdEndRenderPass(current_frame.command_buffer);

        try self.dispatch.endCommandBuffer(current_frame.command_buffer);

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
        try self.dispatch.queueSubmit(self.graphics_queue, 1, @ptrCast([*]const vk.SubmitInfo, &submitInfo), current_frame.frame_done_fence);

        _ = self.dispatch.queuePresentKHR(self.graphics_queue, .{
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

        self.frame_index = @rem(self.frame_index + 1, @intCast(u32, self.frames.len));
    }

    //TODO: use VMA
    //TODO use VMA or alternative
    fn findMemoryTypeIndex(self: Self, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.memory_properties.memory_types[0..self.memory_properties.memory_type_count]) |memory_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(u5, i)) != 0 and memory_type.property_flags.contains(flags)) {
                return @truncate(u32, i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    //TODO: track memory allocations
    pub fn allocate_memory(self: Self, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try self.dispatch.allocateMemory(self.handle, .{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }

    pub fn free_memory(self: Self, memory: vk.DeviceMemory) void {
        self.dispatch.freeMemory(self.handle, memory, null);
    }

    pub fn createPipeline(
        self: Self,
        pipeline_layout: vk.PipelineLayout,
        render_pass: vk.RenderPass,
        vert_code: []align(@alignOf(u32)) const u8,
        frag_code: []align(@alignOf(u32)) const u8,
        input_binding: *const vk.VertexInputBindingDescription,
        input_attributes: []const vk.VertexInputAttributeDescription,
        settings: *const PipelineState,
    ) !vk.Pipeline {
        const vert = try self.dispatch.createShaderModule(self.handle, .{
            .flags = .{},
            .code_size = vert_code.len,
            .p_code = std.mem.bytesAsSlice(u32, vert_code).ptr,
        }, null);
        defer self.dispatch.destroyShaderModule(self.handle, vert, null);

        const frag = try self.dispatch.createShaderModule(self.handle, .{
            .flags = .{},
            .code_size = frag_code.len,
            .p_code = std.mem.bytesAsSlice(u32, frag_code).ptr,
        }, null);
        defer self.dispatch.destroyShaderModule(self.handle, frag, null);

        const pssci = [_]vk.PipelineShaderStageCreateInfo{
            .{
                .flags = .{},
                .stage = .{ .vertex_bit = true },
                .module = vert,
                .p_name = "main",
                .p_specialization_info = null,
            },
            .{
                .flags = .{},
                .stage = .{ .fragment_bit = true },
                .module = frag,
                .p_name = "main",
                .p_specialization_info = null,
            },
        };

        const pvisci = vk.PipelineVertexInputStateCreateInfo{
            .flags = .{},
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = @ptrCast([*]const vk.VertexInputBindingDescription, input_binding),
            .vertex_attribute_description_count = @intCast(u32, input_attributes.len),
            .p_vertex_attribute_descriptions = input_attributes.ptr,
        };

        const piasci = vk.PipelineInputAssemblyStateCreateInfo{
            .flags = .{},
            .topology = .triangle_list,
            .primitive_restart_enable = vk.FALSE,
        };

        const pvsci = vk.PipelineViewportStateCreateInfo{
            .flags = .{},
            .viewport_count = 1,
            .p_viewports = undefined,
            .scissor_count = 1,
            .p_scissors = undefined,
        };

        const prsci = vk.PipelineRasterizationStateCreateInfo{
            .flags = .{},
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = .fill,
            .cull_mode = settings.cull_mode,
            .front_face = .counter_clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        };

        const pmsci = vk.PipelineMultisampleStateCreateInfo{
            .flags = .{},
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = vk.FALSE,
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        };

        var blend_enable: vk.Bool32 = vk.FALSE;
        if (settings.blend_enable) {
            blend_enable = vk.TRUE;
        }

        const pcbas = vk.PipelineColorBlendAttachmentState{
            .blend_enable = vk.TRUE,
            .src_color_blend_factor = settings.src_color_blend_factor,
            .dst_color_blend_factor = settings.dst_color_blend_factor,
            .color_blend_op = settings.color_blend_op,
            .src_alpha_blend_factor = settings.src_alpha_blend_factor,
            .dst_alpha_blend_factor = settings.dst_alpha_blend_factor,
            .alpha_blend_op = settings.alpha_blend_op,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };

        const pcbsci = vk.PipelineColorBlendStateCreateInfo{
            .flags = .{},
            .logic_op_enable = vk.FALSE,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast([*]const vk.PipelineColorBlendAttachmentState, &pcbas),
            .blend_constants = [_]f32{ 0, 0, 0, 0 },
        };

        const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
        const pdsci = vk.PipelineDynamicStateCreateInfo{
            .flags = .{},
            .dynamic_state_count = dynstate.len,
            .p_dynamic_states = &dynstate,
        };

        //TODO: depth testing
        const gpci = vk.GraphicsPipelineCreateInfo{
            .flags = .{},
            .stage_count = 2,
            .p_stages = &pssci,
            .p_vertex_input_state = &pvisci,
            .p_input_assembly_state = &piasci,
            .p_tessellation_state = null,
            .p_viewport_state = &pvsci,
            .p_rasterization_state = &prsci,
            .p_multisample_state = &pmsci,
            .p_depth_stencil_state = null,
            .p_color_blend_state = &pcbsci,
            .p_dynamic_state = &pdsci,
            .layout = pipeline_layout,
            .render_pass = render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        var pipeline: vk.Pipeline = undefined;
        _ = try self.dispatch.createGraphicsPipelines(
            self.handle,
            .null_handle,
            1,
            @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &gpci),
            null,
            @ptrCast([*]vk.Pipeline, &pipeline),
        );
        return pipeline;
    }
};

pub const PipelineState = struct {
    cull_mode: vk.CullModeFlags = .{ .back_bit = true },
    blend_enable: bool = false,
    src_color_blend_factor: vk.BlendFactor = .one,
    dst_color_blend_factor: vk.BlendFactor = .zero,
    color_blend_op: vk.BlendOp = .add,
    src_alpha_blend_factor: vk.BlendFactor = .one,
    dst_alpha_blend_factor: vk.BlendFactor = .zero,
    alpha_blend_op: vk.BlendOp = .add,
};

//TODO Split wrappers by extension maybe?
pub const DeviceDispatch = vk.DeviceWrapper(&.{
    .destroyDevice,
    .getDeviceQueue,
    .createSemaphore,
    .createFence,
    .createImageView,
    .destroyImageView,
    .destroySemaphore,
    .destroyFence,
    .getSwapchainImagesKHR,
    .createSwapchainKHR,
    .destroySwapchainKHR,
    .acquireNextImageKHR,
    .deviceWaitIdle,
    .waitForFences,
    .resetFences,
    .queueSubmit,
    .queuePresentKHR,
    .createCommandPool,
    .destroyCommandPool,
    .allocateCommandBuffers,
    .freeCommandBuffers,
    .queueWaitIdle,
    .createDescriptorSetLayout,
    .destroyDescriptorSetLayout,
    .createDescriptorPool,
    .destroyDescriptorPool,
    .allocateDescriptorSets,
    .createShaderModule,
    .destroyShaderModule,
    .createPipelineLayout,
    .destroyPipelineLayout,
    .createRenderPass,
    .destroyRenderPass,
    .createGraphicsPipelines,
    .destroyPipeline,
    .createFramebuffer,
    .destroyFramebuffer,
    .beginCommandBuffer,
    .endCommandBuffer,
    .allocateMemory,
    .freeMemory,
    .createBuffer,
    .destroyBuffer,
    .getBufferMemoryRequirements,
    .mapMemory,
    .unmapMemory,
    .bindBufferMemory,
    .bindImageMemory,
    .cmdBeginRenderPass,
    .cmdEndRenderPass,
    .cmdBindPipeline,
    .cmdDraw,
    .cmdSetViewport,
    .cmdSetScissor,
    .cmdBindVertexBuffers,
    .cmdBindIndexBuffer,
    .cmdCopyBuffer,
    .cmdPipelineBarrier,
    .cmdBindDescriptorSets,
    .cmdPushConstants,
    .cmdDrawIndexed,
    .createImage,
    .destroyImage,
    .getImageMemoryRequirements,
});
