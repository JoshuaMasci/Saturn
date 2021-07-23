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
    device: Device,

    pub fn init(
        allocator: *Allocator,
        app_name: [*:0]const u8,
        app_version: u32,
    ) !Self {
        var glfw_exts_count: u32 = 0;
        const glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_exts_count);
        var base_dispatch = try BaseDispatch.load(glfwGetInstanceProcAddress);

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = app_version,
            .p_engine_name = saturn_name,
            .engine_version = saturn_version,
            .api_version = VK_API_VERSION_1_2,
        };

        var instance = try base_dispatch.createInstance(.{
            .flags = .{},
            .p_application_info = &app_info,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = glfw_exts_count,
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, glfw_exts),
        }, null);

        var instance_dispatch = try InstanceDispatch.load(instance, glfwGetInstanceProcAddress);

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
            .device = device,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.deinit();
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
