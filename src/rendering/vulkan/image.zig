const std = @import("std");

const vk = @import("vulkan");

const Device = @import("device.zig");
const GpuAllocator = @import("gpu_allocator.zig");

const Self = @This();

device: *Device,

size: [2]u32,
format: vk.Format,
usage: vk.ImageUsageFlags,

handle: vk.Image,
view_handle: vk.ImageView,
allocation: GpuAllocator.Allocation,

pub fn init2D(device: *Device, size: [2]u32, format: vk.Format, usage: vk.ImageUsageFlags, memory_location: GpuAllocator.MemoryLocation) !Self {
    const handle = try device.device.createImage(&.{
        .image_type = .@"2d",
        .format = format,
        .extent = .{ .width = size[0], .height = size[1], .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = usage,
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, null);
    errdefer device.device.destroyImage(handle, null);

    const allocation = try device.gpu_allocator.alloc(device.device.getImageMemoryRequirements(handle), memory_location);
    errdefer device.gpu_allocator.free(allocation);
    try device.device.bindImageMemory(handle, allocation.memory, allocation.offset);

    const view_handle = try device.device.createImageView(&.{
        .view_type = .@"2d",
        .image = handle,
        .format = format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = getFormatAspectMask(format),
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
    errdefer device.device.destroyImageView(view_handle, null);

    return .{
        .device = device,
        .size = size,
        .format = format,
        .usage = usage,
        .handle = handle,
        .view_handle = view_handle,
        .allocation = allocation,
    };
}

pub fn deinit(self: Self) void {
    self.device.device.destroyImageView(self.view_handle, null);
    self.device.device.destroyImage(self.handle, null);
    self.device.gpu_allocator.free(self.allocation);
}

pub fn getFormatAspectMask(format: vk.Format) vk.ImageAspectFlags {
    return switch (format) {
        // Depth-only formats
        .d16_unorm, .d32_sfloat, .x8_d24_unorm_pack32 => .{ .depth_bit = true },

        // Stencil-only formats
        .s8_uint => .{ .stencil_bit = true },

        // Depth-stencil formats
        .d16_unorm_s8_uint, .d24_unorm_s8_uint, .d32_sfloat_s8_uint => .{ .depth_bit = true, .stencil_bit = true },

        // All other formats (color formats)
        else => .{ .color_bit = true },
    };
}
