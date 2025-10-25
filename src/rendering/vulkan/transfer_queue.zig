const std = @import("std");

const vk = @import("vulkan");
const Device = @import("device.zig");
const Buffer = @import("buffer.zig");
const Image = @import("image.zig");
const Backend = @import("backend.zig");

const BufferTransfer = struct {
    src_offset: usize,
    dst: Backend.BufferHandle,
    dst_offset: usize,
    size: usize,
};

pub const TextureTransfer = struct {
    src_offset: usize,
    dst: Backend.ImageHandle,
    final_layout: vk.ImageLayout,
    size: usize,
};

const Self = @This();

allocator: std.mem.Allocator,
device: *Device,

staging_buffer: Buffer,
staging_slice: []u8,
staging_offset: usize = 0,

buffer_transfer_list: std.ArrayList(BufferTransfer) = .empty,
texture_transfer_list: std.ArrayList(TextureTransfer) = .empty,

pub fn init(allocator: std.mem.Allocator, device: *Device, staging_buffer_size: usize) !Self {
    const staging_buffer: Buffer = try .init(device, staging_buffer_size, .{ .transfer_src_bit = true }, .gpu_mappable);
    const staging_slice = staging_buffer.allocation.getMappedByteSlice().?;

    device.setDebugName(.buffer, staging_buffer.handle, "Transfer Buffer");

    return .{
        .allocator = allocator,
        .device = device,
        .staging_buffer = staging_buffer,
        .staging_slice = staging_slice,
    };
}

pub fn deinit(self: *Self) void {
    self.staging_buffer.deinit();
    self.buffer_transfer_list.deinit(self.allocator);
    self.texture_transfer_list.deinit(self.allocator);
}

pub fn hasSpace(self: *const Self, data_size: usize) bool {
    return (self.staging_offset + data_size) < self.staging_slice.len;
}

pub const WriteBufferError = error{
    OutOfMemory,
    StagingBufferFull,
    WriteOutOfBounds,
    InvalidBuffer,
};
pub fn writeBuffer(self: *Self, dst: Backend.BufferHandle, offset: usize, data: []const u8) WriteBufferError!void {
    if ((self.staging_offset + data.len) > self.staging_slice.len) {
        return error.StagingBufferFull;
    }

    // if (self.backend.buffers.get(dst)) |buffer| {
    //     if ((offset + data.len) > buffer.size) {
    //         return error.WriteOutOfBounds;
    //     }
    // } else {
    //     return error.InvalidBuffer;
    // }

    self.buffer_transfer_list.append(self.allocator, .{
        .src_offset = self.staging_offset,
        .dst = dst,
        .dst_offset = offset,
        .size = data.len,
    }) catch return error.OutOfMemory;

    @memcpy(self.staging_slice[self.staging_offset..(self.staging_offset + data.len)], data);
    self.staging_offset += data.len;
}

pub const WriteTextureError = error{
    OutOfMemory,
    StagingBufferFull,
    WriteOutOfBounds,
    InvalidTexture,
};
pub fn writeTexture(self: *Self, dst: Backend.ImageHandle, final_layout: vk.ImageLayout, data: []const u8) WriteTextureError!void {
    if ((self.staging_offset + data.len) > self.staging_slice.len) {
        return error.StagingBufferFull;
    }

    self.texture_transfer_list.append(self.allocator, .{
        .src_offset = self.staging_offset,
        .dst = dst,
        .final_layout = final_layout,
        .size = data.len,
    }) catch return error.OutOfMemory;

    @memcpy(self.staging_slice[self.staging_offset..(self.staging_offset + data.len)], data);
    self.staging_offset += data.len;
}

const rg = @import("render_graph.zig");
pub fn createRenderPass(
    self: *Self,
    temp_allocator: std.mem.Allocator,
) !?rg.RenderPass {
    if (self.buffer_transfer_list.items.len == 0 and self.texture_transfer_list.items.len == 0) {
        return null;
    }

    defer {
        self.buffer_transfer_list.clearRetainingCapacity();
        self.texture_transfer_list.clearRetainingCapacity();
        self.staging_offset = 0;
    }

    const buffer_transfer_list = try temp_allocator.dupe(BufferTransfer, self.buffer_transfer_list.items);
    const texture_transfer_list = try temp_allocator.dupe(TextureTransfer, self.texture_transfer_list.items);

    const build_data = try temp_allocator.create(BuildData);
    build_data.* = .{
        .src_buffer = self.staging_buffer,
        .buffer_transfer_list = buffer_transfer_list,
        .texture_transfer_list = texture_transfer_list,
    };

    var render_pass = try rg.RenderPass.init(temp_allocator, "Transfer Pass");
    render_pass.queue_type = .prefer_async_transfer;
    render_pass.addBuildFn(buildCommandBuffer, build_data);
    return render_pass;
}

const BuildData = struct {
    src_buffer: Buffer,
    buffer_transfer_list: []const BufferTransfer,
    texture_transfer_list: []const TextureTransfer,
};

fn buildCommandBuffer(build_data: ?*anyopaque, backend: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = resources; // autofix
    _ = raster_pass_extent; // autofix

    const data: *BuildData = @ptrCast(@alignCast(build_data.?));

    const src_buffer = data.src_buffer;

    for (data.buffer_transfer_list) |transfer| {
        if (backend.buffers.get(transfer.dst)) |dst_buffer| {
            const region: vk.BufferCopy2 = .{
                .src_offset = transfer.src_offset,
                .dst_offset = transfer.dst_offset,
                .size = transfer.size,
            };

            command_buffer.copyBuffer2(&.{
                .src_buffer = src_buffer.handle,
                .dst_buffer = dst_buffer.handle,
                .region_count = 1,
                .p_regions = @ptrCast(&region),
            });
        }
    }

    for (data.texture_transfer_list) |transfer| {
        if (backend.images.get(transfer.dst)) |dst_texture| {
            var interface = dst_texture.interface();

            const pre_copy_barrier = interface.transitionLazy(.transfer_dst_optimal).?;
            command_buffer.pipelineBarrier2(&.{
                .image_memory_barrier_count = 1,
                .p_image_memory_barriers = @ptrCast(&pre_copy_barrier),
            });

            const region: vk.BufferImageCopy2 = .{
                .buffer_offset = transfer.src_offset,
                .buffer_row_length = 0,
                .buffer_image_height = 0,
                .image_subresource = vk.ImageSubresourceLayers{
                    .aspect_mask = Image.getFormatAspectMask(interface.format),
                    .mip_level = 0,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .image_offset = .{ .x = 0, .y = 0, .z = 0 },
                .image_extent = .{ .width = interface.extent.width, .height = interface.extent.height, .depth = 1 },
            };

            command_buffer.copyBufferToImage2(&.{
                .src_buffer = src_buffer.handle,
                .dst_image = interface.handle,
                .dst_image_layout = .transfer_dst_optimal,
                .region_count = 1,
                .p_regions = @ptrCast(&region),
            });

            const post_copy_barrier = interface.transitionLazy(transfer.final_layout).?;
            command_buffer.pipelineBarrier2(&.{
                .image_memory_barrier_count = 1,
                .p_image_memory_barriers = @ptrCast(&post_copy_barrier),
            });
        }
    }
}
