const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const glfw = @import("glfw_platform.zig");
pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *glfw.c.GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

pub fn makeVkVersion(major: u7, minor: u10, patch: u12) u32 {
    return (@as(u32, major) << 22) | (@as(u32, minor) << 12) | patch;
}

const vk = @import("vulkan");
const VK_API_VERSION_1_2 = vk.makeApiVersion(0, 1, 2, 0);

const saturn_name = "saturn engine";
const saturn_version = vk.makeApiVersion(0, 0, 0, 0);

const BaseDispatch = vk.BaseWrapper(.{
    .CreateInstance,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .DestroyInstance,
    .CreateDevice,
    .DestroySurfaceKHR,
    .EnumeratePhysicalDevices,
    .GetPhysicalDeviceProperties,
    .EnumerateDeviceExtensionProperties,
    .GetPhysicalDeviceSurfaceFormatsKHR,
    .GetPhysicalDeviceSurfacePresentModesKHR,
    .GetPhysicalDeviceSurfaceCapabilitiesKHR,
    .GetPhysicalDeviceQueueFamilyProperties,
    .GetPhysicalDeviceSurfaceSupportKHR,
    .GetPhysicalDeviceMemoryProperties,
    .GetDeviceProcAddr,
    .CreateDebugUtilsMessengerEXT,
    .DestroyDebugUtilsMessengerEXT,
});

const DeviceDispatch = vk.DeviceWrapper(.{ .DestroyDevice, .GetDeviceQueue, .CreateSemaphore, .CreateFence, .CreateImageView, .DestroyImageView, .DestroySemaphore, .DestroyFence, .GetSwapchainImagesKHR, .CreateSwapchainKHR, .DestroySwapchainKHR, .AcquireNextImageKHR, .DeviceWaitIdle, .WaitForFences, .ResetFences, .QueueSubmit, .QueuePresentKHR, .CreateCommandPool, .DestroyCommandPool, .AllocateCommandBuffers, .FreeCommandBuffers, .QueueWaitIdle, .CreateShaderModule, .DestroyShaderModule, .CreatePipelineLayout, .DestroyPipelineLayout, .CreateRenderPass, .DestroyRenderPass, .CreateGraphicsPipelines, .DestroyPipeline, .CreateFramebuffer, .DestroyFramebuffer, .BeginCommandBuffer, .EndCommandBuffer, .AllocateMemory, .FreeMemory, .CreateBuffer, .DestroyBuffer, .GetBufferMemoryRequirements, .MapMemory, .UnmapMemory, .BindBufferMemory, .CmdBeginRenderPass, .CmdEndRenderPass, .CmdBindPipeline, .CmdDraw, .CmdSetViewport, .CmdSetScissor, .CmdBindVertexBuffers, .CmdCopyBuffer, .CmdPipelineBarrier });

var vkb: BaseDispatch = undefined;
var vki: InstanceDispatch = undefined;
var vkd: DeviceDispatch = undefined;

pub const Graphics = struct {
    const Self = @This();

    allocator: *Allocator,
    instance: vk.Instance,
    debug_callback: DebugCallback,
    surface: vk.SurfaceKHR,
    device: Device,
    swapchain: Swapchain,

    temp_semaphore: vk.Semaphore,
    present_semaphore: vk.Semaphore,
    temp_fence: vk.Fence,
    temp_pool: vk.CommandPool,
    temp_buffer: vk.CommandBuffer,

    pub fn init(
        allocator: *Allocator,
        app_name: [*:0]const u8,
        app_version: u32,
        window: glfw.WindowId,
    ) !Self {
        vkb = try BaseDispatch.load(glfwGetInstanceProcAddress);

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

        var instance = try vkb.createInstance(.{
            .flags = .{},
            .p_application_info = &app_info,

            .enabled_layer_count = @intCast(u32, layers.items.len),
            .pp_enabled_layer_names = @ptrCast([*]const [*:0]const u8, layers.items),
            .enabled_extension_count = @intCast(u32, extensions.items.len),
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, extensions.items),
        }, null);

        vki = try InstanceDispatch.load(instance, glfwGetInstanceProcAddress);

        var debug_callback = try DebugCallback.init(instance);

        //Surface
        var surface = try Self.createSurface(instance, window);

        //Device
        var device_count: u32 = undefined;
        _ = try vki.enumeratePhysicalDevices(instance, &device_count, null);

        const pdevices = try allocator.alloc(vk.PhysicalDevice, device_count);
        defer allocator.free(pdevices);

        _ = try vki.enumeratePhysicalDevices(instance, &device_count, pdevices.ptr);

        //TODO pick device and queues
        var pdevice = pdevices[0];
        var graphcis_queue_index: u32 = 0;

        var supports_surface = try vki.getPhysicalDeviceSurfaceSupportKHR(pdevice, graphcis_queue_index, surface);
        if (supports_surface == 0) {
            return error.NoDeviceSurfaceSupport;
        }

        var device = try Device.init(pdevice, 0);

        //Swapchain
        //Hardcoded values
        var window_size = glfw.getWindowSize(window);
        var swapchain_info = SwapchainInfo{
            .image_count = 3,
            .format = vk.SurfaceFormatKHR{
                .format = .b8g8r8a8_srgb,
                .color_space = .srgb_nonlinear_khr,
            },
            .extent = vk.Extent2D{
                .width = @intCast(u32, window_size[0]),
                .height = @intCast(u32, window_size[1]),
            },
            .usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .mode = .mailbox_khr,
        };
        var swapchain = try Swapchain.init(allocator, device, surface, swapchain_info);

        //Temp
        var semaphore = try vkd.createSemaphore(device.device, .{
            .flags = .{},
        }, null);

        var semaphore2 = try vkd.createSemaphore(device.device, .{
            .flags = .{},
        }, null);

        var fence = try vkd.createFence(device.device, .{
            .flags = .{ .signaled_bit = true },
        }, null);

        var pool = try vkd.createCommandPool(device.device, .{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = graphcis_queue_index,
        }, null);

        var buffer: vk.CommandBuffer = undefined;
        try vkd.allocateCommandBuffers(device.device, .{
            .command_pool = pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast([*]vk.CommandBuffer, &buffer));

        return Self{
            .allocator = allocator,
            .instance = instance,
            .debug_callback = debug_callback,
            .surface = surface,
            .device = device,
            .swapchain = swapchain,
            .temp_semaphore = semaphore,
            .present_semaphore = semaphore2,
            .temp_fence = fence,
            .temp_pool = pool,
            .temp_buffer = buffer,
        };
    }

    pub fn deinit(self: Self) void {
        self.device.waitIdle();

        vkd.destroySemaphore(self.device.device, self.temp_semaphore, null);
        vkd.destroySemaphore(self.device.device, self.present_semaphore, null);
        vkd.destroyFence(self.device.device, self.temp_fence, null);
        vkd.destroyCommandPool(self.device.device, self.temp_pool, null);

        self.swapchain.deinit();
        self.device.deinit();
        vki.destroySurfaceKHR(self.instance, self.surface, null);
        self.debug_callback.deinit();
        vki.destroyInstance(self.instance, null);
    }

    fn createSurface(instance: vk.Instance, windowId: glfw.WindowId) !vk.SurfaceKHR {
        var surface: vk.SurfaceKHR = undefined;
        if (glfwCreateWindowSurface(instance, glfw.getWindowHandle(windowId), null, &surface) != .success) {
            return error.SurfaceCreationFailed;
        }
        return surface;
    }

    pub fn draw(self: Self) void {
        var fence = @ptrCast([*]const vk.Fence, &self.temp_fence);
        _ = vkd.waitForFences(self.device.device, 1, fence, 1, std.math.maxInt(u64)) catch {};
        _ = vkd.resetFences(self.device.device, 1, fence) catch {};

        var image_index = self.swapchain.getNextImage(self.temp_semaphore);

        vkd.beginCommandBuffer(self.temp_buffer, .{
            .flags = .{},
            .p_inheritance_info = null,
        }) catch {};

        var image_barrier = vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{},
            .old_layout = .@"undefined",
            .new_layout = .present_src_khr,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.swapchain.images.items[image_index],
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
        vkd.cmdPipelineBarrier(self.temp_buffer, .{ .top_of_pipe_bit = true }, .{ .bottom_of_pipe_bit = true }, .{}, 0, empty_memory, 0, empty_buffer, 1, @ptrCast([*]const vk.ImageMemoryBarrier, &image_barrier));

        vkd.endCommandBuffer(self.temp_buffer) catch {};

        var wait_stages = vk.PipelineStageFlags{
            .color_attachment_output_bit = true,
        };

        const submitInfo = vk.SubmitInfo{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &self.temp_semaphore),
            .p_wait_dst_stage_mask = @ptrCast([*]const vk.PipelineStageFlags, &wait_stages),
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &self.temp_buffer),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast([*]const vk.Semaphore, &self.present_semaphore),
        };
        vkd.queueSubmit(self.device.graphics_queue, 1, @ptrCast([*]const vk.SubmitInfo, &submitInfo), self.temp_fence) catch {};

        _ = vkd.queuePresentKHR(self.device.graphics_queue, .{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &self.present_semaphore),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast([*]const vk.SwapchainKHR, &self.swapchain.handle),
            .p_image_indices = @ptrCast([*]const u32, &image_index),
            .p_results = null,
        }) catch {};
    }
};

const required_device_extensions = [_][]const u8{vk.extension_info.khr_swapchain.name};

const Device = struct {
    const Self = @This();

    pdevice: vk.PhysicalDevice,
    device: vk.Device,
    graphics_queue: vk.Queue,

    //TODO actually pick queue familes for graphics/present/compute/transfer
    fn init(pdevice: vk.PhysicalDevice, graphics_queue_index: u32) !Self {
        const props = vki.getPhysicalDeviceProperties(pdevice);
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

        var device = try vki.createDevice(pdevice, .{
            .flags = .{},
            .queue_create_info_count = 1,
            .p_queue_create_infos = &qci,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = required_device_extensions.len,
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, &required_device_extensions),
            .p_enabled_features = null,
        }, null);

        vkd = try DeviceDispatch.load(device, vki.dispatch.vkGetDeviceProcAddr);

        var graphics_queue = vkd.getDeviceQueue(device, graphics_queue_index, 0);

        return Self{
            .pdevice = pdevice,
            .device = device,
            .graphics_queue = graphics_queue,
        };
    }

    fn deinit(self: Self) void {
        vkd.destroyDevice(self.device, null);
    }

    fn waitIdle(self: Self) void {
        vkd.deviceWaitIdle(self.device) catch panic("Failed to waitIdle", .{});
    }
};

const SwapchainInfo = struct {
    image_count: u32,
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    usage: vk.ImageUsageFlags,
    mode: vk.PresentModeKHR,
};

//pub const SwapchainId = usize;
const Swapchain = struct {
    const Self = @This();

    allocator: *Allocator,
    device: vk.Device,
    pdevice: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,

    handle: vk.SwapchainKHR,

    images: std.ArrayList(vk.Image),

    info: SwapchainInfo,

    fn init(allocator: *Allocator, device: Device, surface: vk.SurfaceKHR, info: SwapchainInfo) !Self {
        const caps = try vki.getPhysicalDeviceSurfaceCapabilitiesKHR(device.pdevice, surface);

        //TEMP
        const queue_family_index = [_]u32{0};

        var create_info = vk.SwapchainCreateInfoKHR{
            .surface = surface,
            .min_image_count = info.image_count,
            .image_format = info.format.format,
            .image_color_space = info.format.color_space,
            .image_extent = info.extent,
            .image_array_layers = 1,
            .image_usage = info.usage,
            .image_sharing_mode = .exclusive,
            .queue_family_index_count = queue_family_index.len,
            .p_queue_family_indices = &queue_family_index,
            .pre_transform = caps.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = info.mode,
            .clipped = vk.TRUE,
            .old_swapchain = .null_handle,
            .flags = .{},
        };
        const handle = try vkd.createSwapchainKHR(device.device, create_info, null);

        var count: u32 = undefined;
        _ = try vkd.getSwapchainImagesKHR(device.device, handle, &count, null);
        var images = try std.ArrayList(vk.Image).initCapacity(allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try images.append(.null_handle);
        }
        _ = try vkd.getSwapchainImagesKHR(device.device, handle, &count, @ptrCast([*]vk.Image, images.items));

        return Self{
            .allocator = allocator,
            .device = device.device,
            .pdevice = device.pdevice,
            .surface = surface,
            .handle = handle,
            .images = images,
            .info = info,
        };
    }

    fn deinit(self: Self) void {
        self.images.deinit();
        vkd.destroySwapchainKHR(self.device, self.handle, null);
    }

    fn getNextImage(self: Self, image_ready: vk.Semaphore) u32 {
        const result = vkd.acquireNextImageKHR(
            self.device,
            self.handle,
            std.math.maxInt(u64),
            image_ready,
            .null_handle,
        ) catch |err| {
            panic("Swapchain.acquireNextImageKHR Failed: {}", .{err});
        };

        return result.image_index;
    }
};

const MemoryUsage = enum {
    Staging,
    CpuRead,
    DeviceLocal,
};

const Buffer = struct {
    device: vk.Device,

    memory: vk.Memory,
    buffer: vk.Buffer,

    fn init(
        device: vk.Device,
        size: u64,
        memory_usage: MemoryUsage,
    ) void {
        return;
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

        var debug_messenger = try vki.createDebugUtilsMessengerEXT(instance, debug_callback_info, null);

        return Self{
            .instance = instance,
            .debug_messenger = debug_messenger,
        };
    }

    fn deinit(self: Self) void {
        vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
    }
};
