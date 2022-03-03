const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vulkan");
pub const AppVersion = vk.makeApiVersion;

const glfw = @import("glfw");

const saturn_name = "Saturn Engine";
const saturn_version = vk.makeApiVersion(0, 0, 0, 0);

pub const Instance = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    handle: vk.Instance,
    dispatch: InstanceDispatch,
    debug_callback: DebugCallback,
    pdevices: []vk.PhysicalDevice,

    pub fn init(
        allocator: std.mem.Allocator,
        app_name: [*:0]const u8,
        app_version: u32,
    ) !Self {
        const vk_proc = @ptrCast(fn (instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction, glfw.getInstanceProcAddress);
        var base_dispatch = try BaseDispatch.load(vk_proc);

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = app_version,
            .p_engine_name = saturn_name,
            .engine_version = saturn_version,
            .api_version = vk.API_VERSION_1_3,
        };

        var extensions = std.ArrayList([*:0]const u8).init(allocator);
        defer extensions.deinit();

        try extensions.append(vk.extension_info.khr_get_physical_device_properties_2.name);

        const glfw_exts = try glfw.getRequiredInstanceExtensions();
        for (glfw_exts) |extension| {
            try extensions.append(extension);
        }

        var layers = std.ArrayList([*:0]const u8).init(allocator);
        defer layers.deinit();

        //Validation
        try extensions.append(vk.extension_info.ext_debug_utils.name);
        try extensions.append(vk.extension_info.ext_debug_report.name);
        try layers.append("VK_LAYER_KHRONOS_validation");

        var handle = try base_dispatch.createInstance(&.{
            .flags = .{},
            .p_application_info = &app_info,
            .enabled_layer_count = @intCast(u32, layers.items.len),
            .pp_enabled_layer_names = @ptrCast([*]const [*:0]const u8, layers.items),
            .enabled_extension_count = @intCast(u32, extensions.items.len),
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, extensions.items),
        }, null);

        var dispatch = try InstanceDispatch.load(handle, vk_proc);

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

        var debug_messenger = try dispatch.createDebugUtilsMessengerEXT(instance, &debug_callback_info, null);

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
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(.C) vk.Bool32 {
    _ = message_types;
    _ = p_user_data;

    if (p_callback_data) |callback_data| {
        var message_level = vk.DebugUtilsMessageSeverityFlagsEXT.fromInt(message_severity);
        if (message_level.verbose_bit_ext) {
            std.log.debug("{s}", .{callback_data.p_message});
        } else if (message_level.info_bit_ext) {
            std.log.info("{s}", .{callback_data.p_message});
        } else if (message_level.warning_bit_ext) {
            std.log.warn("{s}", .{callback_data.p_message});
        } else if (message_level.error_bit_ext) {
            std.log.err("{s}", .{callback_data.p_message});
        } else {
            std.log.err("UNKNOWN Message Severity {s}", .{callback_data.p_message});
        }
    }

    return 0;
}

pub const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
});

pub const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .createDevice = true,
    .destroySurfaceKHR = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceProperties = true,
    .getPhysicalDeviceFeatures2 = true,
    .enumerateDeviceExtensionProperties = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getDeviceProcAddr = true,
    .createDebugUtilsMessengerEXT = true,
    .destroyDebugUtilsMessengerEXT = true,
});
