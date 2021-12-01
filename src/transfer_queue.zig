usingnamespace @import("core.zig");
const vk = @import("vulkan");
usingnamespace @import("vulkan/device.zig");
usingnamespace @import("vulkan/buffer.zig");
usingnamespace @import("vulkan/image.zig");

const ImageTransferQueue = std.ArrayList(struct {
    image: Image,
    staging_buffer: Buffer,
});

pub const TransferQueue = struct {
    const Self = @This();

    allocator: *Allocator,
    device: Device,

    image_transfers: ImageTransferQueue,
    previous_image_transfers: ?ImageTransferQueue,

    pub fn init(
        allocator: *Allocator,
        device: Device,
    ) Self {
        return Self{
            .allocator = allocator,
            .device = device,
            .image_transfers = ImageTransferQueue.init(allocator),
            .previous_image_transfers = null,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.image_transfers.items) |transfer| {
            transfer.staging_buffer.deinit();
        }
        self.image_transfers.deinit();
    }

    pub fn copyToImage(self: *Self, image: Image, comptime Type: type, data: []const Type) void {
        var staging_buffer_size = @intCast(u32, @sizeOf(Type) * data.len);
        var staging_buffer = Buffer.init(self.device, staging_buffer_size, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }) catch {
            std.debug.panic("Failed to create staging buffer", .{});
        };

        staging_buffer.fill(Type, data) catch {
            std.debug.panic("Failed to fill staging buffer", .{});
        };

        self.image_transfers.append(.{
            .image = image,
            .staging_buffer = staging_buffer,
        }) catch {
            std.debug.panic("Failed to append image transfer queue", .{});
        };
    }

    pub fn commitTransfers(self: *Self, command_buffer: vk.CommandBuffer) void {
        for (self.image_transfers.items) |image_transfer| {
            transitionImageLayout(
                self.device,
                command_buffer,
                image_transfer.image.handle,
                .@"undefined",
                .transfer_dst_optimal,
                .{},
                .{ .transfer_write_bit = true },
                .{ .top_of_pipe_bit = true },
                .{ .transfer_bit = true },
            );

            var image_extent: vk.Extent3D = .{
                .width = image_transfer.image.size.width,
                .height = image_transfer.image.size.height,
                .depth = 1,
            };

            var region = vk.BufferImageCopy{
                .buffer_offset = 0,
                .buffer_row_length = 0,
                .buffer_image_height = 0,
                .image_subresource = .{
                    .aspect_mask = .{ .color_bit = true },
                    .mip_level = 0,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .image_offset = .{ .x = 0, .y = 0, .z = 0 },
                .image_extent = image_extent,
            };

            self.device.dispatch.cmdCopyBufferToImage(
                command_buffer,
                image_transfer.staging_buffer.handle,
                image_transfer.image.handle,
                .transfer_dst_optimal,
                1,
                @ptrCast([*]const vk.BufferImageCopy, &region),
            );

            transitionImageLayout(
                self.device,
                command_buffer,
                image_transfer.image.handle,
                .transfer_dst_optimal,
                .shader_read_only_optimal,
                .{ .transfer_write_bit = true },
                .{ .shader_read_bit = true },
                .{ .transfer_bit = true },
                .{ .fragment_shader_bit = true },
            );
        }

        self.previous_image_transfers = self.image_transfers;
        self.image_transfers = ImageTransferQueue.init(self.allocator);
    }

    pub fn clearResources(self: *Self) void {
        if (self.previous_image_transfers) |image_transfers| {
            for (image_transfers.items) |image_transfer| {
                image_transfer.staging_buffer.deinit();
            }
            image_transfers.deinit();
            self.previous_image_transfers = null;
        }
    }
};

fn transitionImageLayout(
    device: Device,
    command_buffer: vk.CommandBuffer,
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    src_access_mask: vk.AccessFlags,
    dst_access_mask: vk.AccessFlags,
    src_stage_mask: vk.PipelineStageFlags,
    dst_stage_mask: vk.PipelineStageFlags,
) void {
    var image_barrier = vk.ImageMemoryBarrier{
        .src_access_mask = src_access_mask,
        .dst_access_mask = dst_access_mask,
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    device.dispatch.cmdPipelineBarrier(
        command_buffer,
        src_stage_mask,
        dst_stage_mask,
        .{},
        0,
        undefined,
        0,
        undefined,
        1,
        @ptrCast([*]const vk.ImageMemoryBarrier, &image_barrier),
    );
}
