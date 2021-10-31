const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vulkan");
const VK_API_VERSION_1_2 = vk.makeApiVersion(0, 1, 2, 0);
pub const AppVersion = vk.makeApiVersion;

const glfw = @import("../glfw/platform.zig");
extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;

const saturn_name = "Saturn Engine";
const saturn_version = vk.makeApiVersion(0, 0, 0, 0);

pub const Instance = struct {
    const Self = @This();

    allocator: *Allocator,
    handle: vk.Instance,
    dispatch: InstanceDispatch,
    debug_callback: DebugCallback,
    pdevices: []vk.PhysicalDevice,

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

        var handle = try base_dispatch.createInstance(.{
            .flags = .{},
            .p_application_info = &app_info,

            .enabled_layer_count = @intCast(u32, layers.items.len),
            .pp_enabled_layer_names = @ptrCast([*]const [*:0]const u8, layers.items),
            .enabled_extension_count = @intCast(u32, extensions.items.len),
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, extensions.items),
        }, null);

        var dispatch = try InstanceDispatch.load(handle, glfwGetInstanceProcAddress);

        var debug_callback = try DebugCallback.init(handle, dispatch);

        var device_count: u32 = undefined;
        _ = try dispatch.enumeratePhysicalDevices(handle, &device_count, null);

        var pdevices: []vk.PhysicalDevice = try allocator.alloc(vk.PhysicalDevice, device_count);
        _ = try dispatch.enumeratePhysicalDevices(handle, &device_count, pdevices.ptr);

        return Self{
            .allocator = allocator,
            .handle = handle,
            .dispatch = dispatch,
            .debug_callback = debug_callback,
            .pdevices = pdevices,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.pdevices);
        self.debug_callback.deinit();
        self.dispatch.destroyInstance(self.handle, null);
    }
};

const DebugCallback = struct {
    const Self = @This();

    instance: vk.Instance,
    dispatch: InstanceDispatch,
    debug_messenger: vk.DebugUtilsMessengerEXT,

    fn init(
        instance: vk.Instance,
        dispatch: InstanceDispatch,
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

        var debug_messenger = try dispatch.createDebugUtilsMessengerEXT(instance, debug_callback_info, null);

        return Self{
            .instance = instance,
            .dispatch = dispatch,
            .debug_messenger = debug_messenger,
        };
    }

    fn deinit(self: Self) void {
        self.dispatch.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
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

pub const BaseDispatch = vk.BaseWrapper(.{
    .CreateInstance,
});

pub const InstanceDispatch = vk.InstanceWrapper(.{
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
