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

    pub fn init(
        allocator: *Allocator,
        device: Device,
    ) Self {
        return Self{
            .allocator = allocator,
            .device = device,
            .image_transfers = ImageTransferQueue.init(allocator),
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
                image_transfer.image,
                .@"undefined",
                .general,
                .{},
                .transfer_write_bit,
            );
        }

        //TODO: this
        self.image_transfers.clearRetainingCapacity();
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
            .aspect_mask = .color_bit,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    device.dispatch.cmdPipelineBarrier(
        device.handle,
        command_buffer,
        .{ .top_of_pipe_bit = true },
        .{ .transfer_bit = true },
        .{},
        0,
        undefined,
        0,
        undefined,
        1,
    );
}
