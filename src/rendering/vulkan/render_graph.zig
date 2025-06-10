const std = @import("std");

const vk = @import("vulkan");

const Window = @import("../../platform/sdl3.zig").Window;
const Device = @import("device.zig");
const BufferHandle = Device.BufferHandle;
const ImageHandle = Device.ImageHandle;
const GpuAllocator = @import("gpu_allocator.zig");

pub const QueueType = enum {
    graphics,
    prefer_async_compute,
    prefer_async_transfer,
};

/// Function should returns amount of data actually written
pub const UploadFn = *const fn (data: ?*anyopaque, dst: []u8) usize;

pub const DownloadFn = *const fn (data: ?*anyopaque, src: []u8) void;

pub const CommandBufferBuildFn = *const fn (
    data: ?*anyopaque,
    device: *Device,
    command_buffer: vk.CommandBufferProxy,
    raster_pass_extent: ?vk.Extent2D,
) void;

pub const TransientBuffer = struct {
    size: usize,
    usage: vk.BufferUsageFlags,
    location: GpuAllocator.MemoryLocation = .gpu_only,
};

pub const RenderGraphBuffer = union(enum) {
    persistent: BufferHandle,
    transient: usize,
};
pub const RenderGraphBufferHandle = struct { buffer_index: usize };

pub const TextureExtent = union(enum) {
    fixed: vk.Extent2D,
    relative: RenderGraphTextureHandle,
};

pub const TransientTexture = struct {
    extent: TextureExtent,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
};

pub const RenderGraphTexture = union(enum) {
    persistent: ImageHandle,
    transient: usize,
    swapchain: usize,
};
pub const RenderGraphTextureHandle = struct { texture_index: usize };

pub const BufferUploadPass = struct {
    target: RenderGraphBufferHandle,
    offset: usize,
    size: usize,
    write_fn: UploadFn,
    write_data: ?*anyopaque,
};

pub const ColorAttachment = struct {
    texture: RenderGraphTextureHandle,
    clear: ?vk.ClearColorValue = null,
    store: bool = true,
};

pub const DepthAttachment = struct {
    texture: RenderGraphTextureHandle,
    clear: ?f32 = null,
    store: bool = true,
};

pub const RasterPass = struct {
    color_attachments: std.ArrayList(ColorAttachment),
    depth_attachment: ?DepthAttachment = null,
};

pub const RenderPass = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    name: []const u8,
    queue_type: QueueType = .graphics,
    raster_pass: ?RasterPass = null,

    build_fn: ?CommandBufferBuildFn = null,
    build_data: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Self {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.raster_pass) |*raster_pass| {
            raster_pass.color_attachments.deinit();
        }
        self.allocator.free(self.name);
    }

    pub fn addColorAttachment(self: *Self, attachment: ColorAttachment) !void {
        if (self.raster_pass == null) {
            self.raster_pass = RasterPass{
                .color_attachments = std.ArrayList(ColorAttachment).init(self.allocator),
            };
        }
        try self.raster_pass.?.color_attachments.append(attachment);
    }

    pub fn addDepthAttachment(self: *Self, attachment: DepthAttachment) void {
        if (self.raster_pass == null) {
            self.raster_pass = RasterPass{
                .color_attachments = std.ArrayList(ColorAttachment).init(self.allocator),
            };
        }
        self.raster_pass.?.depth_attachment = attachment;
    }

    pub fn addBuildFn(self: *Self, build_fn: CommandBufferBuildFn, build_data: ?*anyopaque) void {
        self.build_fn = build_fn;
        self.build_data = build_data;
    }
};

pub const RenderGraph = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    swapchains: std.ArrayList(Window),
    transient_buffers: std.ArrayList(TransientBuffer),
    transient_textures: std.ArrayList(TransientTexture),

    buffers: std.ArrayList(RenderGraphBuffer),
    textures: std.ArrayList(RenderGraphTexture),

    buffer_upload_passes: std.ArrayList(BufferUploadPass),
    render_passes: std.ArrayList(RenderPass),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .swapchains = .init(allocator),
            .transient_buffers = .init(allocator),
            .transient_textures = .init(allocator),
            .buffers = .init(allocator),
            .textures = .init(allocator),
            .buffer_upload_passes = .init(allocator),
            .render_passes = .init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.swapchains.deinit();
        self.transient_buffers.deinit();
        self.transient_textures.deinit();
        self.buffers.deinit();
        self.textures.deinit();
        self.buffer_upload_passes.deinit();
        self.render_passes.deinit();
    }

    pub fn importBuffer(self: *Self, handle: BufferHandle) !RenderGraphBuffer {
        const buffer_index = self.buffers.items.len;
        try self.buffer.append(.{ .persistent = handle });
        return .{ .buffer_index = buffer_index };
    }

    pub fn createTransientBuffer(self: *Self, definition: TransientBuffer) !RenderGraphBufferHandle {
        const transient_index = self.transient_buffers.items.len;
        try self.transient_buffers.append(definition);

        const buffer_index = self.buffers.items.len;
        try self.buffers.append(.{ .transient = transient_index });
        return .{ .buffer_index = buffer_index };
    }

    pub fn importTexture(self: *Self, handle: ImageHandle) !RenderGraphTextureHandle {
        const texture_index = self.textures.items.len;
        try self.textures.append(.{ .persistent = handle });
        return .{ .texture_index = texture_index };
    }

    pub fn createTransientTexture(self: *Self, definition: TransientTexture) !RenderGraphTextureHandle {
        const transient_index = self.transient_textures.items.len;
        try self.transient_textures.append(definition);

        const texture_index = self.textures.items.len;
        try self.textures.append(.{ .transient = transient_index });
        return .{ .texture_index = texture_index };
    }

    pub fn acquireSwapchainTexture(self: *Self, window: Window) !RenderGraphTextureHandle {
        const swapchain_index = self.swapchains.items.len;
        try self.swapchains.append(window);

        const texture_index = self.textures.items.len;
        try self.textures.append(.{ .swapchain = swapchain_index });
        return .{ .texture_index = texture_index };
    }
};
