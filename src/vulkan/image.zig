const vk = @import("vulkan");
const device_allocator = @import("device_allocator.zig");

const Device = @import("device.zig");
const DeviceAllocator = @import("device_allocator.zig");

pub const Description = struct {
    size: [2]u32,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
    memory_usage: DeviceAllocator.MemoryUsage,
};

const Self = @This();

device: *Device,
allocator: ?*DeviceAllocator,
description: Description,
handle: vk.Image,
allocation: DeviceAllocator.Allocation,
view: vk.ImageView,

pub fn init(
    device: *Device,
    allocator: *DeviceAllocator,
    description: Description,
) !Self {

    //Due to a compiler bug, I need to spesify &vk.ImageCreateInfo{} rather than just &.{}
    var image = try device.base.createImage(
        device.handle,
        &vk.ImageCreateInfo{
            .flags = .{},
            .image_type = .@"2d",
            .format = description.format,
            .extent = .{
                .width = description.size[0],
                .height = description.size[1],
                .depth = 1,
            },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .usage = description.usage,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
            .initial_layout = .@"undefined",
        },
        null,
    );

    var memory_requirements = device.base.getImageMemoryRequirements(device.handle, image);
    var allocation = try allocator.allocate(memory_requirements, description.memory_usage);
    try device.base.bindImageMemory(device.handle, image, allocation.memory, allocation.offset);

    //TODO: for depth stencil images
    var view = try device.base.createImageView(
        device.handle,
        &.{
            .flags = .{},
            .image = image,
            .view_type = .@"2d",
            .format = description.format,
            .components = .{ .r = .r, .g = .g, .b = .b, .a = .a },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        },
        null,
    );

    return Self{
        .device = device,
        .allocator = allocator,
        .description = description,
        .handle = image,
        .allocation = allocation,
        .view = view,
    };
}

pub fn initSwapchainImage(
    device: *Device,
    swapchain_image: vk.Image,
    description: Description,
) !Self {
    var view = try device.base.createImageView(
        device.handle,
        &.{
            .flags = .{},
            .image = swapchain_image,
            .view_type = .@"2d",
            .format = description.format,
            .components = .{ .r = .r, .g = .g, .b = .b, .a = .a },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        },
        null,
    );

    return Self{
        .device = device,
        .allocator = null,
        .description = description,
        .handle = swapchain_image,
        .allocation = .{
            .memory = .null_handle,
            .offset = 0,
            .size = 0,
            .mapped_ptr = null,
        },
        .view = view,
    };
}

pub fn deinit(self: Self) void {
    self.device.base.destroyImageView(self.device.handle, self.view, null);

    if (self.allocator) |allocator| {
        //Only destroy image if this struct allocated it
        self.device.base.destroyImage(self.device.handle, self.handle, null);
        allocator.free(self.allocation);
    }
}
