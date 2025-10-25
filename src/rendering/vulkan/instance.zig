const std = @import("std");

const vk = @import("vulkan");
pub const makeVersion = vk.makeApiVersion;

const PhysicalDeviceInfo = @import("physical_device.zig");
const Device = @import("device.zig");

pub const AppInfo = struct {
    name: [:0]const u8,
    version: vk.Version,
};

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    info: PhysicalDeviceInfo,

    pub fn supportsSurface(self: PhysicalDevice, instance: vk.InstanceProxy, surface: vk.SurfaceKHR) bool {
        var supports_present: vk.Bool32 = .false;

        //Only supports present on graphics_queue
        if (self.info.queues.graphics) |graphics_queue| {
            supports_present = instance.getPhysicalDeviceSurfaceSupportKHR(self.handle, graphics_queue, surface);
        }

        return supports_present == .true;
    }
};

pub const ScoreFn = *const fn (instance: *vk.InstanceProxy, physics_device: vk.PhysicalDevice) ?usize;

const Self = @This();

allocator: std.mem.Allocator,
base: vk.BaseWrapper,
instance: vk.InstanceProxy,

physical_devices: []PhysicalDevice,

debug_messager: ?DebugMessenger,

pub fn init(
    allocator: std.mem.Allocator,
    loader: vk.PfnGetInstanceProcAddr,
    platform_extensions: []const [*c]const u8,
    info: AppInfo,
    debug: bool,
) !Self {
    const base = vk.BaseWrapper.load(loader);

    const app_info = vk.ApplicationInfo{
        .p_application_name = info.name,
        .application_version = @bitCast(info.version),
        .p_engine_name = info.name,
        .engine_version = @bitCast(info.version),
        .api_version = @bitCast(vk.API_VERSION_1_3),
    };

    var instance_layers: std.ArrayList([*c]const u8) = .empty;
    defer instance_layers.deinit(allocator);

    var instance_extentions: std.ArrayList([*c]const u8) = .empty;
    defer instance_extentions.deinit(allocator);
    try instance_extentions.appendSlice(allocator, platform_extensions);

    if (debug) {
        try instance_layers.append(allocator, "VK_LAYER_KHRONOS_validation");
        try instance_extentions.append(allocator, "VK_EXT_debug_utils");
    }

    const instance_handle = try base.createInstance(&.{
        .p_application_info = &app_info,
        .pp_enabled_layer_names = @ptrCast(instance_layers.items.ptr),
        .enabled_layer_count = @intCast(instance_layers.items.len),
        .pp_enabled_extension_names = @ptrCast(instance_extentions.items.ptr),
        .enabled_extension_count = @intCast(instance_extentions.items.len),
    }, null);

    const instance_wrapper = try allocator.create(vk.InstanceWrapper);
    errdefer allocator.destroy(instance_wrapper);
    instance_wrapper.* = vk.InstanceWrapper.load(instance_handle, base.dispatch.vkGetInstanceProcAddr.?);
    const instance = vk.InstanceProxy.init(instance_handle, instance_wrapper);

    const physical_device_handles = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(physical_device_handles);

    const physical_devices = try allocator.alloc(PhysicalDevice, physical_device_handles.len);

    for (physical_device_handles, 0..) |handle, i| {
        physical_devices[i] = .{
            .handle = handle,
            .info = try .init(allocator, instance, handle),
        };
    }

    const debug_messager: ?DebugMessenger =
        if (debug)
            DebugMessenger.init(
                instance,
                .{ .verbose_bit_ext = false, .info_bit_ext = false, .warning_bit_ext = true, .error_bit_ext = true },
                .{ .general_bit_ext = true, .validation_bit_ext = true, .performance_bit_ext = true },
            )
        else
            null;

    return .{
        .allocator = allocator,
        .base = base,
        .instance = instance,
        .physical_devices = physical_devices,
        .debug_messager = debug_messager,
    };
}

pub fn deinit(self: Self) void {
    if (self.debug_messager) |debug_messager| {
        debug_messager.deinit(self.instance);
    }

    self.allocator.free(self.physical_devices);

    self.instance.destroyInstance(null);
    self.allocator.destroy(self.instance.wrapper);
}

pub fn createDevice(self: Self, device_index: usize) !Device {
    return .init(
        self.allocator,
        self.instance,
        self.physical_devices[device_index],
        self.debug_messager != null,
    );
}

const DebugMessenger = struct {
    handle: vk.DebugUtilsMessengerEXT,

    fn init(instance: vk.InstanceProxy, message_severity: vk.DebugUtilsMessageSeverityFlagsEXT, message_types: vk.DebugUtilsMessageTypeFlagsEXT) DebugMessenger {
        return .{
            .handle = instance.createDebugUtilsMessengerEXT(&.{
                .message_severity = message_severity,
                .message_type = message_types,
                .pfn_user_callback = DebugMessenger.callback,
            }, null) catch |err| blk: {
                std.log.err("Failed to create vk.DebugUtilsMessengerEXT: {}", .{err});
                break :blk .null_handle;
            },
        };
    }

    fn deinit(self: @This(), instance: vk.InstanceProxy) void {
        instance.destroyDebugUtilsMessengerEXT(self.handle, null);
    }

    fn callback(
        message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
        message_types: vk.DebugUtilsMessageTypeFlagsEXT,
        p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
        p_user_data: ?*anyopaque,
    ) callconv(vk.vulkan_call_conv) vk.Bool32 {
        _ = message_types; // autofix
        _ = p_user_data; // autofix

        if (p_callback_data) |callback_data| {
            if (callback_data.p_message) |message| {
                if (message_severity.info_bit_ext or message_severity.verbose_bit_ext) {
                    std.log.info("vulkan: {s}", .{message});
                } else if (message_severity.warning_bit_ext) {
                    std.log.warn("vulkan: {s}", .{message});
                } else if (message_severity.error_bit_ext) {
                    std.log.err("vulkan: {s}", .{message});
                }
            }
        }

        return .false;
    }
};
