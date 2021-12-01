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
    image_view: vk.ImageView,

    format: vk.Format,
    size: vk.Extent2D,

    pub fn init(device: Device, format: vk.Format, size: vk.Extent2D, memory_type: vk.MemoryPropertyFlags) !Self {
        var image = try device.dispatch.createImage(
            device.handle,
            .{
                .flags = .{},
                .image_type = .@"2d",
                .format = format,
                .extent = .{
                    .width = size.width,
                    .height = size.height,
                    .depth = 1,
                },
                .mip_levels = 1,
                .array_layers = 1,
                .samples = .{ .@"1_bit" = true },
                .tiling = .optimal,
                .usage = .{
                    .sampled_bit = true,
                    .transfer_dst_bit = true,
                },
                .sharing_mode = .exclusive,
                .queue_family_index_count = 0,
                .p_queue_family_indices = undefined,
                .initial_layout = .@"undefined",
            },
            null,
        );

        var mem_reqs = device.dispatch.getImageMemoryRequirements(device.handle, image);
        var memory = try device.allocate_memory(mem_reqs, memory_type);
        try device.dispatch.bindImageMemory(device.handle, image, memory, 0);

        return Self{
            .device = device,
            .handle = image,
            .memory = memory,
            .image_view = vk.ImageView.null_handle,
            .format = format,
            .size = size,
        };
    }

    pub fn deinit(self: Self) void {
        self.device.dispatch.destroyImageView(self.device.handle, self.image_view, null);
        self.device.dispatch.destroyImage(self.device.handle, self.handle, null);
        self.device.free_memory(self.memory);
    }

    pub fn createImageView(self: *Self) !void {
        self.image_view = try self.device.dispatch.createImageView(
            self.device.handle,
            .{
                .flags = .{},
                .image = self.handle,
                .view_type = .@"2d",
                .format = self.format,
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
    }
};
