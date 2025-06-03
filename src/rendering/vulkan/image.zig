const std = @import("std");

const vk = @import("vulkan");

const Device = @import("device.zig");
const GpuAllocator = @import("gpu_allocator.zig");

pub const Interface = struct {
    layout: vk.ImageLayout = .undefined,
    extent: vk.Extent2D = .{ .width = 0, .height = 0 },
    format: vk.Format = .undefined,
    usage: vk.ImageUsageFlags = .{},
    handle: vk.Image = .null_handle,
    view_handle: vk.ImageView = .null_handle,
    sampled_binding: ?u32 = null,

    pub fn transitionLazy(self: *@This(), new_layout: vk.ImageLayout) ?vk.ImageMemoryBarrier {
        if (new_layout == self.layout) {
            return null;
        }

        const old_layout = self.layout;
        self.layout = new_layout;

        return .{
            .src_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
            .dst_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
            .old_layout = old_layout,
            .new_layout = new_layout,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.handle,
            .subresource_range = .{
                .aspect_mask = getFormatAspectMask(self.format),
                .base_array_layer = 0,
                .layer_count = 1,
                .base_mip_level = 0,
                .level_count = 1,
            },
        };
    }
};

const Self = @This();

device: *Device,

layout: vk.ImageLayout = .undefined,
extent: vk.Extent2D,
format: vk.Format,
usage: vk.ImageUsageFlags,

handle: vk.Image,
view_handle: vk.ImageView,
allocation: GpuAllocator.Allocation,

sampled_binding: ?u32 = null,

pub fn init2D(device: *Device, extent: vk.Extent2D, format: vk.Format, usage: vk.ImageUsageFlags, memory_location: GpuAllocator.MemoryLocation) !Self {
    const handle = try device.device.createImage(&.{
        .image_type = .@"2d",
        .format = format,
        .extent = .{ .width = extent.width, .height = extent.height, .depth = 1 },
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
        .extent = extent,
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

pub fn interface(self: Self) Interface {
    return .{
        .layout = self.layout,
        .extent = self.extent,
        .format = self.format,
        .usage = self.usage,
        .handle = self.handle,
        .view_handle = self.view_handle,
        .sampled_binding = self.sampled_binding,
    };
}

pub fn uploadImageData(
    self: *Self,
    device: *Device,
    queue: Device.Queue,
    final_layout: vk.ImageLayout,
    data: []const u8,
) !void {
    var command_buffers: [1]vk.CommandBuffer = undefined;
    try device.device.allocateCommandBuffers(&.{
        .command_pool = queue.command_pool,
        .level = vk.CommandBufferLevel.primary,
        .command_buffer_count = 1,
    }, &command_buffers);
    defer device.device.freeCommandBuffers(queue.command_pool, @intCast(command_buffers.len), &command_buffers);
    const command_buffer = command_buffers[0];

    const fence = try device.device.createFence(&.{}, null);
    defer device.device.destroyFence(fence, null);

    try device.device.beginCommandBuffer(command_buffer, &.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const subresource_range = vk.ImageSubresourceRange{
        .aspect_mask = getFormatAspectMask(self.format),
        .base_mip_level = 0,
        .level_count = 1,
        .base_array_layer = 0,
        .layer_count = 1,
    };

    const barrier_to_transfer_dst = vk.ImageMemoryBarrier{
        .src_access_mask = .{},
        .dst_access_mask = .{ .transfer_write_bit = true },
        .old_layout = .undefined,
        .new_layout = .transfer_dst_optimal,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = self.handle,
        .subresource_range = subresource_range,
    };
    device.device.cmdPipelineBarrier(
        command_buffer,
        .{ .top_of_pipe_bit = true },
        .{ .transfer_bit = true },
        .{},
        0,
        null,
        0,
        null,
        1,
        (&barrier_to_transfer_dst)[0..1],
    );

    const Buffer = @import("buffer.zig");
    const buffer = try Buffer.init(device, data.len, .{ .transfer_src_bit = true }, .cpu_only);
    defer buffer.deinit();

    const byte_ptr: [*]u8 = @ptrCast(buffer.allocation.mapped_ptr.?);
    @memcpy(byte_ptr[0..data.len], data);

    const buffer_image_copy = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = vk.ImageSubresourceLayers{
            .aspect_mask = getFormatAspectMask(self.format),
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{ .width = self.extent.width, .height = self.extent.height, .depth = 1 },
    };

    device.device.cmdCopyBufferToImage(
        command_buffer,
        buffer.handle,
        self.handle,
        .transfer_dst_optimal,
        1,
        (&buffer_image_copy)[0..1],
    );

    const barrier_to_shader_read = vk.ImageMemoryBarrier{
        .src_access_mask = .{ .transfer_write_bit = true },
        .dst_access_mask = .{ .shader_read_bit = true },
        .old_layout = .transfer_dst_optimal,
        .new_layout = final_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = self.handle,
        .subresource_range = subresource_range,
    };

    device.device.cmdPipelineBarrier(
        command_buffer,
        .{ .transfer_bit = true },
        .{ .all_commands_bit = true },
        .{},
        0,
        null,
        0,
        null,
        1,
        (&barrier_to_shader_read)[0..1],
    );

    try device.device.endCommandBuffer(command_buffer);

    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = &command_buffers,
    };
    try device.device.queueSubmit(queue.handle, 1, (&submit_info)[0..1], fence);
    _ = try device.device.waitForFences(1, (&fence)[0..1], 1, std.math.maxInt(u64));

    self.layout = final_layout;
}
