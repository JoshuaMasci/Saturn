const std = @import("std");

const vk = @import("vulkan");

const Window = @import("../../platform/sdl3.zig").Window;
const Device = @import("device.zig");
const BufferHandle = Device.BufferHandle;
const ImageHandle = Device.ImageHandle;

pub const QueueType = enum {
    graphics,
    prefer_async_compute,
    prefer_async_transfer,
};

pub const TransientBuffer = struct {
    size: usize,
    usage: vk.BufferUsageFlags,
};

pub const TextureExtent = union(enum) {
    fixed: vk.Extent2D,
    relative: RenderGraphTextureHandle,
};

pub const TransientTexture = struct {
    extent: TextureExtent,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
};

pub const RenderGraphBuffer = union(enum) {
    persistent: BufferHandle,
    transient: usize,
};

pub const RenderGraphTexture = union(enum) {
    persistent: ImageHandle,
    transient: usize,
    swapchain: usize,
};
pub const RenderGraphTextureHandle = struct { texture_index: usize };

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

pub const CommandBufferBuildFn = *const fn (
    device: *Device,
    command_buffer: vk.CommandBufferProxy,
    raster_pass_extent: ?vk.Extent2D,
    user_data: ?*anyopaque,
) void;

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
    transient_textures: std.ArrayList(TransientTexture),

    textures: std.ArrayList(RenderGraphTexture),

    render_passes: std.ArrayList(RenderPass),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .swapchains = .init(allocator),
            .transient_textures = .init(allocator),
            .textures = .init(allocator),
            .render_passes = .init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.swapchains.deinit();
        self.transient_textures.deinit();
        self.textures.deinit();
        self.render_passes.deinit();
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
