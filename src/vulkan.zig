const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});
pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
pub extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *GLFWwindow, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;

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

const DeviceDispatch = vk.DeviceWrapper(.{
    .DestroyDevice,
    .GetDeviceQueue,
    .CreateSemaphore,
    .CreateFence,
    .CreateImageView,
    .DestroyImageView,
    .DestroySemaphore,
    .DestroyFence,
    .GetSwapchainImagesKHR,
    .CreateSwapchainKHR,
    .DestroySwapchainKHR,
    .AcquireNextImageKHR,
    .DeviceWaitIdle,
    .WaitForFences,
    .ResetFences,
    .QueueSubmit,
    .QueuePresentKHR,
    .CreateCommandPool,
    .DestroyCommandPool,
    .AllocateCommandBuffers,
    .FreeCommandBuffers,
    .QueueWaitIdle,
    .CreateShaderModule,
    .DestroyShaderModule,
    .CreatePipelineLayout,
    .DestroyPipelineLayout,
    .CreateRenderPass,
    .DestroyRenderPass,
    .CreateGraphicsPipelines,
    .DestroyPipeline,
    .CreateFramebuffer,
    .DestroyFramebuffer,
    .BeginCommandBuffer,
    .EndCommandBuffer,
    .AllocateMemory,
    .FreeMemory,
    .CreateBuffer,
    .DestroyBuffer,
    .GetBufferMemoryRequirements,
    .MapMemory,
    .UnmapMemory,
    .BindBufferMemory,
    .CmdBeginRenderPass,
    .CmdEndRenderPass,
    .CmdBindPipeline,
    .CmdDraw,
    .CmdSetViewport,
    .CmdSetScissor,
    .CmdBindVertexBuffers,
    .CmdCopyBuffer,
});

//var vkb: BaseDispatch = undefined;
//var vki: InstanceDispatch = undefined;
var vkd: DeviceDispatch = undefined;

pub const Graphics = struct {
    const Self = @This();

    vkb: BaseDispatch,
    vki: InstanceDispatch,
    //vkd: DeviceDispatch,

    instance: vk.Instance,
    debug_callback: DebugCallback,
    device: Device,

    pub fn init(
        allocator: *Allocator,
        app_name: [*:0]const u8,
        app_version: u32,
    ) !Self {
        var base_dispatch = try BaseDispatch.load(glfwGetInstanceProcAddress);

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = app_version,
            .p_engine_name = saturn_name,
            .engine_version = saturn_version,
            .api_version = VK_API_VERSION_1_2,
        };

        var glfw_exts_count: u32 = 0;
        const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);

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

        var instance = try base_dispatch.createInstance(.{
            .flags = .{},
            .p_application_info = &app_info,

            .enabled_layer_count = @intCast(u32, layers.items.len),
            .pp_enabled_layer_names = @ptrCast([*]const [*:0]const u8, layers.items),
            .enabled_extension_count = @intCast(u32, extensions.items.len),
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, extensions.items),
        }, null);

        var instance_dispatch = try InstanceDispatch.load(instance, glfwGetInstanceProcAddress);

        var debug_callback = try DebugCallback.init(instance, instance_dispatch);

        var device_count: u32 = undefined;
        _ = try instance_dispatch.enumeratePhysicalDevices(instance, &device_count, null);

        const pdevices = try allocator.alloc(vk.PhysicalDevice, device_count);
        defer allocator.free(pdevices);

        _ = try instance_dispatch.enumeratePhysicalDevices(instance, &device_count, pdevices.ptr);

        //TODO pick device
        var pdevice = pdevices[0];

        var device = try Device.init(instance_dispatch, pdevice, 0);

        return Self{
            .vkb = base_dispatch,
            .vki = instance_dispatch,
            .instance = instance,
            .debug_callback = debug_callback,
            .device = device,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.deinit();
        self.debug_callback.deinit();
        self.vki.destroyInstance(self.instance, null);
    }
};

const required_device_extensions = [_][]const u8{vk.extension_info.khr_swapchain.name};

const Device = struct {
    const Self = @This();

    pdevice: vk.PhysicalDevice,
    device: vk.Device,
    graphics_queue: vk.Queue,

    //TODO actually pick queue familes for graphics/present/compute/transfer
    fn init(vki: InstanceDispatch, pdevice: vk.PhysicalDevice, graphics_queue_index: u32) !Self {
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

    fn deinit(self: *Self) void {
        vkd.destroyDevice(self.device, null);
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
    vki: InstanceDispatch,
    debug_messenger: vk.DebugUtilsMessengerEXT,

    fn init(
        instance: vk.Instance,
        vki: InstanceDispatch,
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
            .vki = vki,
            .debug_messenger = debug_messenger,
        };
    }

    fn deinit(self: *Self) void {
        self.vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
    }
};
