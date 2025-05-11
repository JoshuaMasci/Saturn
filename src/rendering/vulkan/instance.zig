const std = @import("std");

const vk = @import("vulkan");
pub const makeVersion = vk.makeApiVersion;

const Device = @import("device.zig");

pub const AppInfo = struct {
    name: [:0]const u8,
    version: vk.Version,
};

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    graphics_queue_index: ?u32 = null,
    compute_queue_index: ?u32 = null,
    transfer_queue_index: ?u32 = null,

    properties: vk.PhysicalDeviceProperties,
};

pub const ScoreFn = *const fn (instance: *vk.InstanceProxy, physics_device: vk.PhysicalDevice) ?usize;

const Self = @This();

allocator: std.mem.Allocator,
base: vk.BaseWrapper,
instance: vk.InstanceProxy,

physical_devices: []PhysicalDevice,

pub fn init(
    allocator: std.mem.Allocator,
    loader: vk.PfnGetInstanceProcAddr,
    platform_extensions: []const [*c]const u8,
    info: AppInfo,
) !Self {
    const base = vk.BaseWrapper.load(loader);

    const app_info = vk.ApplicationInfo{
        .p_application_name = info.name,
        .application_version = @bitCast(info.version),
        .p_engine_name = info.name,
        .engine_version = @bitCast(info.version),
        .api_version = @bitCast(vk.API_VERSION_1_3),
    };

    var instance_layers = std.ArrayList([*c]const u8).init(allocator);
    defer instance_layers.deinit();

    try instance_layers.append("VK_LAYER_KHRONOS_validation");

    var instance_extentions = std.ArrayList([*c]const u8).init(allocator);
    defer instance_extentions.deinit();
    try instance_extentions.appendSlice(platform_extensions);

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
        const properties = instance.getPhysicalDeviceProperties(handle);

        physical_devices[i] = .{
            .handle = handle,
            .graphics_queue_index = 0,
            .properties = properties,
        };
    }

    return .{
        .allocator = allocator,
        .base = base,
        .instance = instance,
        .physical_devices = physical_devices,
    };
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.physical_devices);

    self.instance.destroyInstance(null);
    self.allocator.destroy(self.instance.wrapper);
}

pub fn pickDevice(self: *const Self, surface_opt: ?vk.SurfaceKHR) ?usize {
    _ = surface_opt; // autofix
    _ = self; // autofix
    return null;
}

pub fn createDevice(self: Self, device_index: usize) !Device {
    std.log.info("Creating Vulkan Device {s}", .{self.physical_devices[device_index].properties.device_name});

    return Device.init(
        self.allocator,
        self.instance,
        self.physical_devices[device_index].handle,
    );
}
