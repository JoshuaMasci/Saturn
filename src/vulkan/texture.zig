const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vk.zig");

usingnamespace @import("device_resources.zig");

pub const Texture = struct {
    const Self = @This();

    device: vk.Device,

    //handle: vk.Image,
    //memory: vk.DeviceMemory,

    pub fn init(device: *DeviceResources, create_info: vk.ImageCreateInfo, memory_type: vk.MemoryPropertyFlags) !Self {
        var image = try vk.vkd.createImage(
            device.device,
            create_info,
            null,
        );
        return Self{
            .device = device.device,
            .handle = image,
        };
    }

    pub fn deinit(self: *Self) void {}
};
