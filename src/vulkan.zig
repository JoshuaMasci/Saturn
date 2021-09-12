const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;
usingnamespace @import("resource_deleter.zig");

const glfw = @import("glfw_platform.zig");
pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *glfw.c.GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

pub const vk = @import("vk.zig");
const VK_API_VERSION_1_2 = vk.makeApiVersion(0, 1, 2, 0);
pub const AppVersion = vk.makeApiVersion;

usingnamespace @import("swapchain.zig");

const saturn_name = "saturn engine";
const saturn_version = vk.makeApiVersion(0, 0, 0, 0);

pub const ALL_SHADER_STAGES = vk.ShaderStageFlags{
    .vertex_bit = true,
    .tessellation_control_bit = true,
    .tessellation_evaluation_bit = true,
    .geometry_bit = true,
    .fragment_bit = true,
    .compute_bit = true,
    .task_bit_nv = true,
    .mesh_bit_nv = true,
    .raygen_bit_khr = true,
    .any_hit_bit_khr = true,
    .closest_hit_bit_khr = true,
    .miss_bit_khr = true,
    .intersection_bit_khr = true,
    .callable_bit_khr = true,
};

pub const MaxDeviceCount: u32 = 8;

pub const Instance = struct {
    const Self = @This();

    allocator: *Allocator,
    instance: vk.Instance,
    debug_callback: DebugCallback,
    surface: vk.SurfaceKHR,

    pdevices: []vk.PhysicalDevice,
    devices: []?Device,

    pub fn init(
        allocator: *Allocator,
        app_name: [*:0]const u8,
        app_version: u32,
        window: glfw.WindowId,
    ) !Self {
        vk.vkb = try vk.BaseDispatch.load(glfwGetInstanceProcAddress);

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = app_version,
            .p_engine_name = saturn_name,
            .engine_version = saturn_version,
            .api_version = VK_API_VERSION_1_2,
        };

        var glfw_exts_count: u32 = 0;
        const glfw_exts = glfw.c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);

        var extensions = std.ArrayList([*:0]const u8).init(allocator);
        defer extensions.deinit();
        var i: u32 = 0;
        while (i < glfw_exts_count) : (i += 1) {
            try extensions.append(@ptrCast([*:0]const u8, glfw_exts[i]));
        }

        var layers = std.ArrayList([*:0]const u8).init(allocator);
        defer layers.deinit();

        //Validation
        try extensions.append(vk.extension_info.ext_debug_utils.name);
        try extensions.append(vk.extension_info.ext_debug_report.name);
        try layers.append("VK_LAYER_KHRONOS_validation");

        var instance = try vk.vkb.createInstance(.{
            .flags = .{},
            .p_application_info = &app_info,

            .enabled_layer_count = @intCast(u32, layers.items.len),
            .pp_enabled_layer_names = @ptrCast([*]const [*:0]const u8, layers.items),
            .enabled_extension_count = @intCast(u32, extensions.items.len),
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, extensions.items),
        }, null);

        vk.vki = try vk.InstanceDispatch.load(instance, glfwGetInstanceProcAddress);

        var debug_callback = try DebugCallback.init(instance);

        //Surface
        var surface = try Self.createSurface(instance, window);

        var device_count: u32 = undefined;
        _ = try vk.vki.enumeratePhysicalDevices(instance, &device_count, null);

        var pdevices: []vk.PhysicalDevice = try allocator.alloc(vk.PhysicalDevice, device_count);
        _ = try vk.vki.enumeratePhysicalDevices(instance, &device_count, pdevices.ptr);

        var devices = try allocator.alloc(?Device, device_count);
        for (devices) |*entry| {
            entry.* = null;
        }

        return Self{
            .allocator = allocator,
            .instance = instance,
            .debug_callback = debug_callback,
            .surface = surface,
            .pdevices = pdevices,
            .devices = devices,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.devices) |*option_device| {
            if (option_device.*) |*device| {
                device.deinit();
            }
        }

        vk.vki.destroySurfaceKHR(self.instance, self.surface, null);

        self.allocator.free(self.devices);
        self.allocator.free(self.pdevices);

        self.debug_callback.deinit();
        vk.vki.destroyInstance(self.instance, null);
    }

    fn createSurface(instance: vk.Instance, windowId: glfw.WindowId) !vk.SurfaceKHR {
        var surface: vk.SurfaceKHR = undefined;
        if (glfwCreateWindowSurface(instance, glfw.getWindowHandle(windowId), null, &surface) != .success) {
            return error.SurfaceCreationFailed;
        }
        return surface;
    }

    pub fn createDevice(self: *Self, device_index: u32, frames_in_flight: u32) !void {

        //TODO pick queues
        var pdevice = self.pdevices[device_index];
        var graphics_queue_index: u32 = 0;

        var supports_surface = try vk.vki.getPhysicalDeviceSurfaceSupportKHR(pdevice, graphics_queue_index, self.surface);
        if (supports_surface == 0) {
            return error.NoDeviceSurfaceSupport;
        }

        self.devices[device_index] = try Device.init(self.allocator, pdevice, self.surface, graphics_queue_index, frames_in_flight);
    }

    pub fn destoryDevice(self: *Self, device_index: u32) void {
        if (self.devices[device_index]) |*device| {
            device.deinit();
        }
        self.devices[device_index] = null;
    }

    pub fn getDevice(self: *Self, device_index: u32) !*Device {
        if (self.devices[device_index]) |*device| {
            return device;
        } else {
            return error.DeviceNotInitialized;
        }
    }
};

const DeviceFrame = struct {
    const Self = @This();
    device: vk.Device,
    image_ready_semaphore: vk.Semaphore,
    present_semaphore: vk.Semaphore,
    frame_done_fence: vk.Fence,
    command_buffer: vk.CommandBuffer,

    fn init(
        device: vk.Device,
        pool: vk.CommandPool,
    ) !Self {
        var image_ready_semaphore = try vk.vkd.createSemaphore(device, .{
            .flags = .{},
        }, null);

        var present_semaphore = try vk.vkd.createSemaphore(device, .{
            .flags = .{},
        }, null);

        var frame_done_fence = try vk.vkd.createFence(device, .{
            .flags = .{ .signaled_bit = true },
        }, null);

        var command_buffer: vk.CommandBuffer = undefined;
        try vk.vkd.allocateCommandBuffers(device, .{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast([*]vk.CommandBuffer, &command_buffer));

        return Self{
            .device = device,
            .image_ready_semaphore = image_ready_semaphore,
            .present_semaphore = present_semaphore,
            .frame_done_fence = frame_done_fence,
            .command_buffer = command_buffer,
        };
    }

    fn deinit(self: Self) void {
        vk.vkd.destroySemaphore(self.device, self.image_ready_semaphore, null);
        vk.vkd.destroySemaphore(self.device, self.present_semaphore, null);
        vk.vkd.destroyFence(self.device, self.frame_done_fence, null);
    }
};

pub const Device = struct {
    const Self = @This();

    allocator: *Allocator,
    pdevice: vk.PhysicalDevice,
    device: vk.Device,

    graphics_queue: vk.Queue,
    command_pool: vk.CommandPool,

    frames: []DeviceFrame,
    frame_index: u32,
    swapchain_index: u32,

    //TODO one swapchain per surface
    swapchain: Swapchain,

    resources: DeviceResources,

    //TODO actually pick queue familes for graphics/present/compute/transfer
    fn init(
        allocator: *Allocator,
        pdevice: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        graphics_queue_index: u32,
        frames_in_flight: u32,
    ) !Self {
        const required_device_extensions = [_][]const u8{vk.extension_info.khr_swapchain.name};

        const props = vk.vki.getPhysicalDeviceProperties(pdevice);
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

        var device = try vk.vki.createDevice(pdevice, .{
            .flags = .{},
            .queue_create_info_count = 1,
            .p_queue_create_infos = &qci,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = required_device_extensions.len,
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, &required_device_extensions),
            .p_enabled_features = null,
        }, null);

        vk.vkd = try vk.DeviceDispatch.load(device, vk.vki.dispatch.vkGetDeviceProcAddr);

        var graphics_queue = vk.vkd.getDeviceQueue(device, graphics_queue_index, 0);

        var command_pool = try vk.vkd.createCommandPool(device, .{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = graphics_queue_index,
        }, null);

        var frames = try allocator.alloc(DeviceFrame, frames_in_flight);
        for (frames) |*frame| {
            frame.* = try DeviceFrame.init(device, command_pool);
        }

        var swapchain = try Swapchain.init(allocator, device, pdevice, surface);

        var resources = try DeviceResources.init(
            allocator,
            pdevice,
            device,
            .{
                .push_constant_size = 128,
                .storage_buffer = 2048,
            },
            frames_in_flight,
        );

        return Self{
            .allocator = allocator,
            .pdevice = pdevice,
            .device = device,
            .graphics_queue = graphics_queue,
            .command_pool = command_pool,
            .frames = frames,
            .frame_index = 0,
            .swapchain_index = 0,
            .swapchain = swapchain,
            .resources = resources,
        };
    }

    fn deinit(self: *Self) void {
        self.waitIdle();

        self.resources.deinit();

        self.swapchain.deinit();
        for (self.frames) |frame| {
            frame.deinit();
        }
        self.allocator.free(self.frames);
        vk.vkd.destroyCommandPool(self.device, self.command_pool, null);
        vk.vkd.destroyDevice(self.device, null);
    }

    pub fn waitIdle(self: Self) void {
        vk.vkd.deviceWaitIdle(self.device) catch panic("Failed to deviceWaitIdle", .{});
    }

    pub fn beginFrame(self: *Self) !?vk.CommandBuffer {
        var current_frame = &self.frames[self.frame_index];

        var fence = @ptrCast([*]const vk.Fence, &current_frame.frame_done_fence);
        _ = try vk.vkd.waitForFences(self.device, 1, fence, 1, std.math.maxInt(u64));

        self.resources.current_frame = self.frame_index;
        self.resources.flushResources();

        if (self.swapchain.getNextImage(current_frame.image_ready_semaphore)) |index| {
            self.swapchain_index = index;
        } else {
            //Swapchain invlaid don't render this frame
            return null;
        }

        _ = try vk.vkd.resetFences(self.device, 1, fence);

        try vk.vkd.beginCommandBuffer(current_frame.command_buffer, .{
            .flags = .{},
            .p_inheritance_info = null,
        });

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

        vk.vkd.cmdSetViewport(current_frame.command_buffer, 0, 1, @ptrCast([*]const vk.Viewport, &viewport));
        vk.vkd.cmdSetScissor(current_frame.command_buffer, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor));

        vk.vkd.cmdBeginRenderPass(
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

        vk.vkd.cmdBindDescriptorSets(
            current_frame.command_buffer,
            .graphics,
            self.resources.pipeline_layout,
            0,
            1,
            @ptrCast([*]const vk.DescriptorSet, &self.resources.descriptor_set),
            0,
            undefined,
        );

        return current_frame.command_buffer;
    }

    pub fn endFrame(self: *Self) !void {
        var current_frame = &self.frames[self.frame_index];

        vk.vkd.cmdEndRenderPass(current_frame.command_buffer);

        try vk.vkd.endCommandBuffer(current_frame.command_buffer);

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
        try vk.vkd.queueSubmit(self.graphics_queue, 1, @ptrCast([*]const vk.SubmitInfo, &submitInfo), current_frame.frame_done_fence);

        _ = vk.vkd.queuePresentKHR(self.graphics_queue, .{
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

    pub fn createPipeline(
        self: Self,
        vert_code: []align(@alignOf(u32)) const u8,
        frag_code: []align(@alignOf(u32)) const u8,
        input_binding: *const vk.VertexInputBindingDescription,
        input_attributes: []const vk.VertexInputAttributeDescription,
    ) !vk.Pipeline {
        const vert = try vk.vkd.createShaderModule(self.device, .{
            .flags = .{},
            .code_size = vert_code.len,
            .p_code = std.mem.bytesAsSlice(u32, vert_code).ptr,
        }, null);
        defer vk.vkd.destroyShaderModule(self.device, vert, null);

        const frag = try vk.vkd.createShaderModule(self.device, .{
            .flags = .{},
            .code_size = frag_code.len,
            .p_code = std.mem.bytesAsSlice(u32, frag_code).ptr,
        }, null);
        defer vk.vkd.destroyShaderModule(self.device, frag, null);

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
            .cull_mode = .{},
            .front_face = .clockwise,
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

        const pcbas = vk.PipelineColorBlendAttachmentState{
            .blend_enable = vk.TRUE,
            .src_color_blend_factor = .src_alpha,
            .dst_color_blend_factor = .one_minus_src_alpha,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .src_alpha,
            .dst_alpha_blend_factor = .one_minus_src_alpha,
            .alpha_blend_op = .add,
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
            .layout = self.resources.pipeline_layout,
            .render_pass = self.swapchain.render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        var pipeline: vk.Pipeline = undefined;
        _ = try vk.vkd.createGraphicsPipelines(
            self.device,
            .null_handle,
            1,
            @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &gpci),
            null,
            @ptrCast([*]vk.Pipeline, &pipeline),
        );
        return pipeline;
    }

    pub fn destroyPipeline(self: Self, pipeline: vk.Pipeline) void {
        vk.vkd.destroyPipeline(self.device, pipeline, null);
    }
};

const ResourceBindingCounts = struct {
    push_constant_size: u32,
    storage_buffer: u32,
    // var sampled_image,
    // var storage_image,
    // var sampler,
    // var acceleration_structure,
};

const BufferResource = struct {
    index: u32,
    buffer: Buffer,
};

const DeviceResources = struct {
    const Self = @This();

    allocator: *Allocator,
    pdevice: vk.PhysicalDevice,
    device: vk.Device,
    memory_properties: vk.PhysicalDeviceMemoryProperties,

    descriptor_layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,

    descriptor_pool: vk.DescriptorPool,
    descriptor_set: vk.DescriptorSet,

    //Non Descriptor Buffers
    buffers: std.AutoHashMap(u32, Buffer),
    buffer_index_next: u32 = 0,
    buffer_freed_indexes: std.ArrayList(u32),

    //Resource Deleters
    current_frame: u32 = 0,
    buffer_deleter: ResourceDeleter(Buffer),

    pub fn init(allocator: *Allocator, pdevice: vk.PhysicalDevice, device: vk.Device, binding_counts: ResourceBindingCounts, frames_in_flight: u32) !Self {
        var memory_properties = vk.vki.getPhysicalDeviceMemoryProperties(pdevice);

        const bindings = [_]vk.DescriptorSetLayoutBinding{.{
            .binding = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = binding_counts.storage_buffer,
            .stage_flags = ALL_SHADER_STAGES,
            .p_immutable_samplers = null,
        }};

        var descriptor_layout = try vk.vkd.createDescriptorSetLayout(
            device,
            .{
                .flags = .{},
                .binding_count = bindings.len,
                .p_bindings = @ptrCast([*]const vk.DescriptorSetLayoutBinding, &bindings[0]),
            },
            null,
        );

        var push_constant_range = vk.PushConstantRange{
            .stage_flags = ALL_SHADER_STAGES,
            .offset = 0,
            .size = binding_counts.push_constant_size,
        };

        var pipeline_layout = try vk.vkd.createPipelineLayout(device, .{
            .flags = .{},
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &descriptor_layout),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, &push_constant_range),
        }, null);

        const pools = [_]vk.DescriptorPoolSize{
            .{
                .type_ = .storage_buffer,
                .descriptor_count = binding_counts.storage_buffer,
            },
        };

        var descriptor_pool = try vk.vkd.createDescriptorPool(device, .{
            .flags = .{},
            .max_sets = 1,
            .pool_size_count = pools.len,
            .p_pool_sizes = @ptrCast([*]const vk.DescriptorPoolSize, &pools[0]),
        }, null);

        var descriptor_set: vk.DescriptorSet = .null_handle;
        _ = try vk.vkd.allocateDescriptorSets(
            device,
            .{
                .descriptor_pool = descriptor_pool,
                .descriptor_set_count = 1,
                .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &descriptor_layout),
            },
            @ptrCast([*]vk.DescriptorSet, &descriptor_set),
        );

        var buffers = std.AutoHashMap(u32, Buffer).init(allocator);
        var buffer_freed_indexes = std.ArrayList(u32).init(allocator);
        var buffer_deleter = try ResourceDeleter(Buffer).init(allocator, frames_in_flight);

        return Self{
            .allocator = allocator,
            .pdevice = pdevice,
            .device = device,
            .memory_properties = memory_properties,
            .descriptor_layout = descriptor_layout,
            .pipeline_layout = pipeline_layout,
            .descriptor_pool = descriptor_pool,
            .descriptor_set = descriptor_set,

            .buffers = buffers,
            .buffer_freed_indexes = buffer_freed_indexes,
            .buffer_deleter = buffer_deleter,
        };
    }

    fn deinit(self: *Self) void {
        var iterator = self.buffers.iterator();
        while (iterator.next()) |buffer| {
            buffer.value_ptr.deinit();
        }

        vk.vkd.destroyDescriptorPool(self.device, self.descriptor_pool, null);
        vk.vkd.destroyPipelineLayout(self.device, self.pipeline_layout, null);
        vk.vkd.destroyDescriptorSetLayout(self.device, self.descriptor_layout, null);

        self.buffers.deinit();
        self.buffer_freed_indexes.deinit();
        self.buffer_deleter.deinit();
    }

    //TODO use VMA or alternative
    fn findMemoryTypeIndex(self: Self, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.memory_properties.memory_types[0..self.memory_properties.memory_type_count]) |memory_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(u5, i)) != 0 and memory_type.property_flags.contains(flags)) {
                return @truncate(u32, i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: Self, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try vk.vkd.allocateMemory(self.device, .{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }

    fn getBufferIndex(self: *Self) u32 {
        var new_index: u32 = undefined;
        if (self.buffer_freed_indexes.items.len > 0) {
            new_index = self.buffer_freed_indexes.pop();
        } else {
            new_index = self.buffer_index_next;
            self.buffer_index_next += 1;
        }

        return new_index;
    }

    pub fn createBuffer(
        self: *Self,
        size: u32,
        usage: vk.BufferUsageFlags,
        memory_type: vk.MemoryPropertyFlags,
    ) !u32 {
        var index = self.getBufferIndex();
        try self.buffers.put(index, try Buffer.init(self, size, usage, memory_type));
        return index;
    }

    pub fn createBufferFill(
        self: *Self,
        size: u32,
        usage: vk.BufferUsageFlags,
        memory_type: vk.MemoryPropertyFlags,
        comptime DataType: type,
        data: []const DataType,
    ) !u32 {
        var index = self.getBufferIndex();
        var buffer = try Buffer.init(self, size, usage, memory_type);
        try buffer.fill(DataType, data);
        try self.buffers.put(index, buffer);
        return index;
    }

    pub fn destoryBuffer(self: *Self, index: u32) void {
        //TODO add it to a delete queue
        var buffer_optional = self.buffers.fetchRemove(index);

        if (buffer_optional) |buffer| {
            self.buffer_deleter.append(self.current_frame, buffer.value);
            self.buffer_freed_indexes.append(index) catch {
                panic("Failed to append freed index", .{});
            };
        }
    }

    pub fn getBuffer(self: Self, index: u32) ?Buffer {
        return self.buffers.get(index);
    }

    fn flushResources(self: *Self) void {
        self.buffer_deleter.flush(self.current_frame);
        // for (self.deleted_buffers[self.current_frame].items) |resource| {
        //     resource.buffer.deinit();
        //     self.buffer_freed_indexes.append(resource.index) catch {
        //         panic("Failed to append freed index", .{});
        //     };
        // }
        // self.deleted_buffers[self.current_frame].clearRetainingCapacity();
    }
};

pub const Buffer = struct {
    const Self = @This();

    device: vk.Device,

    handle: vk.Buffer,
    memory: vk.DeviceMemory,

    size: u32,
    usage: vk.BufferUsageFlags,

    pub fn init(device: *DeviceResources, size: u32, usage: vk.BufferUsageFlags, memory_type: vk.MemoryPropertyFlags) !Self {
        const buffer = try vk.vkd.createBuffer(device.device, .{
            .flags = .{},
            .size = size,
            .usage = usage,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
        }, null);
        const mem_reqs = vk.vkd.getBufferMemoryRequirements(device.device, buffer);
        const memory = try device.allocate(mem_reqs, memory_type);
        try vk.vkd.bindBufferMemory(device.device, buffer, memory, 0);

        return Self{
            .device = device.device,
            .handle = buffer,
            .memory = memory,
            .size = size,
            .usage = usage,
        };
    }

    pub fn deinit(self: Self) void {
        vk.vkd.destroyBuffer(self.device, self.handle, null);
        vk.vkd.freeMemory(self.device, self.memory, null);
    }

    pub fn fill(
        self: Self,
        comptime DataType: type,
        data: []const DataType,
    ) !void {
        //TODO staging buffers and bound checks
        var gpu_memory = try vk.vkd.mapMemory(self.device, self.memory, 0, vk.WHOLE_SIZE, .{});
        var gpu_slice = @ptrCast([*]DataType, @alignCast(@alignOf(DataType), gpu_memory));
        defer vk.vkd.unmapMemory(self.device, self.memory);
        std.mem.copy(DataType, gpu_slice[0..data.len], data);
    }
};

fn debugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT.IntType,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT.IntType,
    p_callback_data: *const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: *c_void,
) callconv(.C) vk.Bool32 {
    //TODO log levels
    std.log.warn("{s}", .{p_callback_data.p_message});
    return 0;
}

const DebugCallback = struct {
    const Self = @This();

    instance: vk.Instance,
    debug_messenger: vk.DebugUtilsMessengerEXT,

    fn init(
        instance: vk.Instance,
    ) !Self {
        var debug_callback_info = vk.DebugUtilsMessengerCreateInfoEXT{
            .flags = .{},
            .message_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
                //.verbose_bit_ext = true,
                //.info_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = vk.DebugUtilsMessageTypeFlagsEXT{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
            },
            .pfn_user_callback = debugCallback,
            .p_user_data = null,
        };

        var debug_messenger = try vk.vki.createDebugUtilsMessengerEXT(instance, debug_callback_info, null);

        return Self{
            .instance = instance,
            .debug_messenger = debug_messenger,
        };
    }

    fn deinit(self: Self) void {
        vk.vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
    }
};
