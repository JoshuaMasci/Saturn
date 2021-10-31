usingnamespace @import("core.zig");

const glfw = @import("glfw/platform.zig");
extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *glfw.c.GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

const vk = @import("vulkan");
usingnamespace @import("vulkan/instance.zig");
usingnamespace @import("vulkan/device.zig");
usingnamespace @import("vulkan/swapchain.zig");

const imgui = @import("Imgui.zig");
const resources = @import("resources");

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

    imgui_layer: imgui.Layer,

    pub fn init(allocator: *Allocator, window: *glfw.c.GLFWwindow) !Self {
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

        var device_frame = try DeviceFrame.init(device, graphics_command_pool);

        var imgui_layer = try imgui.Layer.init(allocator, device, swapchain.render_pass);

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
            .imgui_layer = imgui_layer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.waitIdle();
        self.imgui_layer.deinit();
        self.device_frame.deinit();
        self.swapchain.deinit();
        self.device.dispatch.destroyCommandPool(self.device.handle, self.graphics_command_pool, null);
        self.device.deinit();
        self.instance.dispatch.destroySurfaceKHR(self.instance.handle, self.surface, null);
        self.instance.deinit();
    }

    pub fn update(self: Self, window: glfw.WindowId) void {
        self.imgui_layer.update(window);
    }

    pub fn render(self: *Self) !void {
        var begin_result = try self.beginFrame();
        if (begin_result) |command_buffer| {
            self.imgui_layer.beginFrame();
            try self.imgui_layer.endFrame(command_buffer);
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

        try self.device.dispatch.beginCommandBuffer(current_frame.command_buffer, .{
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

fn createSurface(instance: vk.Instance, window: *glfw.c.GLFWwindow) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if (glfwCreateWindowSurface(instance, window, null, &surface) != .success) {
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
