const std = @import("std");

const vk = @import("vulkan");
const BufferHandle = @import("backend.zig").BufferHandle;
const ImageHandle = @import("backend.zig").ImageHandle;
const Window = @import("../../platform/sdl3.zig").Window;

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
    transient: usize,
    persistent: BufferHandle,
};

pub const RenderGraphTexture = union(enum) {
    transient: usize,
    persistent: ImageHandle,
    swapchain: usize,
};

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
    image: RenderGraphTexture,
    usage_info: TextureUsageInfo,
};

pub const RenderPassDefinition = struct {
    name: []const u8,
    queue_type: QueueType = .graphics,

    // buffer_usage: []const RenderPassBufferUsage,
    // texture_usage: []const RenderPassTextureUsage,
    // build_commands: ?CommandBufferBuildFn = null,
    // user_data: ?*anyopaque = null,
};

pub const RenderGraphDefinition = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    transient_buffers: std.ArrayList(TransientBufferDefinition),
    transient_textures: std.ArrayList(TransientTextureDefinition),
    swapchains: std.ArrayList(Window),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .transient_buffers = .init(allocator),
            .transient_textures = .init(allocator),
            .swapchains = .init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.transient_buffers.deinit();
        self.transient_buffers.deinit();
        self.swapchains.deinit();
    }

    pub fn acquireSwapchainTexture(self: *Self, window: Window) !RenderGraphTexture {
        try self.swapchains.append(window);
        return .{ .swapchain = self.swapchains.items.len };
    }

    pub fn createTransientTexture(self: *Self, definition: TransientTextureDefinition) !RenderGraphTexture {
        try self.transient_textures.append(definition);
        return .{ .transient = self.transient_textures.items.len };
    }
};
