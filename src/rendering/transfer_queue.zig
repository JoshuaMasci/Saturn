const std = @import("std");

const saturn = @import("../root.zig");

pub const BufferUpload = struct {
    dst: saturn.BufferHandle,
    offset: usize,
    data: []const u8,
};

const BufferCopy = struct {
    src: saturn.BufferHandle,
    src_offset: u64,

    dst: saturn.BufferHandle,
    dst_offset: u64,

    size: u64,
};

const BufferTextureCopy = struct {
    src: saturn.BufferHandle,
    src_offset: u64,

    dst: saturn.TextureHandle,
    dst_mip_level: u32,

    extent: saturn.TextureExtent,
};

const Self = @This();

allocator: std.mem.Allocator,
gpu_device: saturn.DeviceInterface,

buffer_copies: std.ArrayList(BufferCopy) = .empty,
buffer_texture_copies: std.ArrayList(BufferTextureCopy) = .empty,

pub fn init(allocator: std.mem.Allocator, gpu_device: saturn.DeviceInterface) Self {
    return .{
        .allocator = allocator,
        .gpu_device = gpu_device,
    };
}

pub fn deinit(self: *Self) void {
    self.buffer_copies.deinit(self.allocator);
    self.buffer_texture_copies.deinit(self.allocator);
}

pub fn addBufferUpload(self: *Self, buffer: saturn.BufferHandle, offset: usize, data: []const u8) saturn.Error!void {
    //TODO: better lifetime for this, as it will be deleted in FRAMES-IN-FLIGHT, so a resubmitted frame would panic on trying to access this
    const staging_buffer: saturn.BufferHandle = try self.gpu_device.createBuffer(.{ .name = "Staging Buffer", .size = data.len, .usage = .{ .transfer_src = true }, .memory = .cpu_to_gpu });
    defer self.gpu_device.destroyBuffer(staging_buffer);

    const staging_slice: []u8 = self.gpu_device.getBufferInfo(staging_buffer).?.mapped_slice.?;
    @memcpy(staging_slice[0..data.len], data);

    try self.buffer_copies.append(self.allocator, .{
        .src = staging_buffer,
        .src_offset = 0,
        .dst = buffer,
        .dst_offset = offset,
        .size = data.len,
    });
}

/// Same as addBufferUpload but it creates only a single staging buffer for the whole copy
pub fn addBulkBufferUpload(self: *Self, uploads: []const BufferUpload) saturn.Error!void {
    if (uploads.len == 0) {
        return;
    }

    const src_offsets = try self.allocator.alloc(u64, uploads.len);
    defer self.allocator.free(src_offsets);

    var offset: u64 = 0;
    for (src_offsets, uploads) |*src_offset, upload| {
        src_offset.* = offset;

        // IDK if I need to realign
        // but this but it seems like a safe bet to not try to do buffer copy on weird alignments
        offset += std.mem.alignForward(u64, offset + upload.data.len, 16);
    }
    const total_bytes = offset;

    //TODO: better lifetime for this, as it will be deleted in FRAMES-IN-FLIGHT, so a resubmitted frame would panic on trying to access this
    const staging_buffer: saturn.BufferHandle = try self.gpu_device.createBuffer(.{ .name = "Staging Buffer", .size = total_bytes, .usage = .{ .transfer_src = true }, .memory = .cpu_to_gpu });
    defer self.gpu_device.destroyBuffer(staging_buffer);

    const staging_slice: []u8 = self.gpu_device.getBufferInfo(staging_buffer).?.mapped_slice.?;

    for (src_offsets, uploads) |src_offset, upload| {
        @memcpy(staging_slice[src_offset..(src_offset + upload.data.len)], upload.data);
        try self.buffer_copies.append(self.allocator, .{
            .src = staging_buffer,
            .src_offset = src_offset,
            .dst = upload.dst,
            .dst_offset = upload.offset,
            .size = upload.data.len,
        });
    }
}

//TODO: mips and sub-regions
pub fn addTextureUpload(self: *Self, texture: saturn.TextureHandle, data: []const u8) saturn.Error!void {

    //TODO: better lifetime for this, as it will be deleted in FRAMES-IN-FLIGHT, so a resubmitted frame would panic on trying to access this
    const staging_buffer: saturn.BufferHandle = try self.gpu_device.createBuffer(.{ .name = "Staging Buffer", .size = data.len, .usage = .{ .transfer_src = true }, .memory = .cpu_to_gpu });
    defer self.gpu_device.destroyBuffer(staging_buffer);

    const staging_slice: []u8 = self.gpu_device.getBufferInfo(staging_buffer).?.mapped_slice.?;
    @memcpy(staging_slice[0..data.len], data);

    const extent = self.gpu_device.getTextureInfo(texture).?.extent;

    try self.buffer_texture_copies.append(self.allocator, .{
        .src = staging_buffer,
        .src_offset = 0,
        .dst = texture,
        .dst_mip_level = 0,
        .extent = extent,
    });
}

pub fn buildPasses(self: *Self, render_graph: *saturn.RenderGraph) saturn.Error!void {
    if (self.buffer_copies.items.len == 0 and self.buffer_texture_copies.items.len == 0) {
        return;
    }

    const callback_ctx = try render_graph.dupe(CallbackData, .{});

    const pass = try render_graph.addTransferPass("Transfer Pass", callback_ctx, transferCallback);

    if (self.buffer_copies.items.len != 0) {
        callback_ctx.buffer_copies = try render_graph.alloc(CallbackBufferCopy, self.buffer_copies.items.len);
        for (callback_ctx.buffer_copies, self.buffer_copies.items) |*dst, src| {
            const dst_buffer = try render_graph.importBuffer(src.dst);
            try render_graph.addBufferUsage(pass, dst_buffer, .transfer_write);
            dst.* = .{
                .size = src.size,
                .src = src.src,
                .src_offset = src.src_offset,
                .dst = dst_buffer,
                .dst_offset = src.dst_offset,
            };
        }
        self.buffer_copies.clearRetainingCapacity();
    }

    if (self.buffer_texture_copies.items.len != 0) {
        const transition_pass = try render_graph.addTransferPass("Transition Pass", null, transitionCallback);

        callback_ctx.buffer_texture_copies = try render_graph.alloc(CallbackBufferTextureCopy, self.buffer_texture_copies.items.len);
        for (callback_ctx.buffer_texture_copies, self.buffer_texture_copies.items) |*dst, src| {
            const dst_texture = try render_graph.importTexture(src.dst);
            try render_graph.addTextureUsage(pass, dst_texture, .transfer_write);
            dst.* = .{
                .src = src.src,
                .src_offset = src.src_offset,
                .dst = dst_texture,
                .dst_mip_level = src.dst_mip_level,
                .extent = src.extent,
            };

            //HACK for the moment since IDK what layout it should be in after upload
            try render_graph.addTextureUsage(transition_pass, dst_texture, .graphics_sampled_read);
        }

        self.buffer_texture_copies.clearRetainingCapacity();
    }
}

const CallbackBufferCopy = struct {
    src: saturn.BufferHandle,
    src_offset: u64,

    dst: saturn.RGBufferHandle,
    dst_offset: u64,

    size: u64,
};

const CallbackBufferTextureCopy = struct {
    src: saturn.BufferHandle,
    src_offset: u64,

    dst: saturn.RGTextureHandle,
    dst_mip_level: u32,

    extent: saturn.TextureExtent,
};

const CallbackData = struct {
    buffer_copies: []CallbackBufferCopy = &.{},
    buffer_texture_copies: []CallbackBufferTextureCopy = &.{},
};

fn transferCallback(ctx: ?*anyopaque, cmd: saturn.TransferCommandEncoder) void {
    const data: *const CallbackData = @ptrCast(@alignCast(ctx));

    for (data.buffer_copies) |copy| {
        const region: saturn.BufferCopyRegion = .{
            .src_offset = copy.src_offset,
            .dst_offset = copy.dst_offset,
            .size = copy.size,
        };
        cmd.copyBuffer(.from(copy.src), .from(copy.dst), &.{region});
    }

    for (data.buffer_texture_copies) |copy| {
        const region: saturn.BufferTextureCopyRegion = .{
            .buffer_offset = copy.src_offset,

            .texture_mip_level = copy.dst_mip_level,
            .texture_offset = @splat(0),
            .extent = copy.extent,
        };

        cmd.copyBufferToTexture(.from(copy.src), .from(copy.dst), &.{region});
    }
}

fn transitionCallback(ctx: ?*anyopaque, cmd: saturn.TransferCommandEncoder) void {
    _ = ctx; // autofix
    _ = cmd; // autofix
}
