const std = @import("std");

const vk = @import("vulkan");

const Window = @import("../../platform/sdl3.zig").Window;
const BufferHandle = @import("backend.zig").BufferHandle;
const ImageHandle = @import("backend.zig").ImageHandle;

pub const QueueType = enum {
    graphics,
    prefer_async_compute,
    prefer_async_transfer,
};

pub const BufferUsageInfo = struct {
    access_flags: vk.AccessFlags,
    pipeline_stages: vk.PipelineStageFlags,
    read_only: bool,
};

pub const TextureUsageInfo = struct {
    access_flags: vk.AccessFlags,
    pipeline_stages: vk.PipelineStageFlags,
    layout: vk.ImageLayout,
    read_only: bool,
};

pub const TransientBufferDefinition = struct {
    size: usize,
    usage: vk.BufferUsageFlags,
};

pub const TransientTextureDefinition = struct {
    extent: [2]u32,
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

pub const CommandBufferBuildFn = *const fn (
    device: vk.Device,
    command_buffer: vk.CommandBufferProxy,
    user_data: ?*anyopaque,
) void;

pub const RenderPassBufferUsage = struct {
    buffer: RenderGraphBuffer,
    usage_info: BufferUsageInfo,
};

pub const RenderPassTextureUsage = struct {
    texture: RenderGraphTextureHandle,
    usage_info: TextureUsageInfo,
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

pub const RasterPassDefinition = struct {
    color_attachments: []ColorAttachment,
    depth_attachment: ?DepthAttachment,
};

pub const RenderPassDefinition = struct {
    name: []const u8,
    queue_type: QueueType = .graphics,
    raster_pass: ?RasterPassDefinition = null,

    // buffer_usage: []const RenderPassBufferUsage,
    // texture_usage: []const RenderPassTextureUsage,
    // build_commands: ?CommandBufferBuildFn = null,
    // user_data: ?*anyopaque = null,
};

pub const RenderGraphDefinition = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    swapchains: std.ArrayList(Window),
    transient_textures: std.ArrayList(TransientTextureDefinition),

    textures: std.ArrayList(RenderGraphTexture),

    render_passes: std.ArrayList(RenderPassDefinition),

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

    pub fn createTransientTexture(self: *Self, definition: TransientTextureDefinition) !RenderGraphTextureHandle {
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
