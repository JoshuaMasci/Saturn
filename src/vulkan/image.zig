const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vk.zig");
usingnamespace @import("device.zig");

pub const Image = struct {
    const Self = @This();

    device: Device,
    handle: vk.Image,
    memory: vk.DeviceMemory,

    size: vk.Extent3D,

    pub fn init(device: Device, create_info: vk.ImageCreateInfo, memory_type: vk.MemoryPropertyFlags) !Self {
        var image = try device.dispatch.createImage(
            device.handle,
            create_info,
            null,
        );

        var mem_reqs = device.dispatch.getImageMemoryRequirements(device.handle, image);
        var memory = try device.allocate_memory(mem_reqs, memory_type);
        try device.dispatch.bindImageMemory(device.handle, image, memory, 0);

        return Self{
            .device = device,
            .handle = image,
            .memory = memory,
            .size = create_info.extent,
        };
    }

    pub fn deinit(self: Self) void {
        self.device.dispatch.destroyImage(self.device.handle, self.handle, null);
        self.device.free_memory(self.memory);
    }
};
