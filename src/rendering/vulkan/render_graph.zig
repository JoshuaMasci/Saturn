const std = @import("std");

const vk = @import("vulkan");

pub const QueueType = enum {
    graphics,
    prefer_async_compute,
    prefer_async_transfer,
};

pub const BufferHandle = usize;
pub const ImageHandle = usize;
pub const SwapchainHandle = usize;

pub const BufferUsageInfo = struct {
    access_flags: vk.AccessFlags,
    pipeline_stages: vk.PipelineStageFlags,
    read_only: bool,
};

pub const ImageUsageInfo = struct {
    access_flags: vk.AccessFlags,
    pipeline_stages: vk.PipelineStageFlags,
    layout: vk.ImageLayout,
    read_only: bool,
};

pub const BufferDefinition = union(enum) {
    transient: struct {
        size: usize,
        usage: vk.BufferUsageFlags,
    },
    persistent: BufferHandle,
};

pub const ImageExtent = struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
};

pub const ImageDefinition = union(enum) {
    transient: struct {
        extent: ImageExtent,
        format: vk.Format,
        usage: vk.ImageUsageFlags,
    },
    persistent: ImageHandle,
    swapchain: SwapchainHandle,
};

pub const CommandBufferBuildFn = *const fn (
    device: vk.Device,
    command_buffer: vk.CommandBufferProxy,
    user_data: ?*anyopaque,
) void;

pub const RenderPassBuffer = struct {
    buffer_index: usize,
    usage_info: BufferUsageInfo,
};

pub const RenderPassImage = struct {
    image_index: usize,
    usage_info: ImageUsageInfo,
};

pub const RenderPassDefinition = struct {
    name: []const u8,
    queue_type: QueueType,
    buffers: []const RenderPassBuffer,
    images: []const RenderPassImage,
    build_commands: CommandBufferBuildFn,
    user_data: ?*anyopaque = null,
};

pub const RenderGraphInput = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(BufferDefinition),
    images: std.ArrayList(ImageDefinition),
    render_passes: std.ArrayList(RenderPassDefinition),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .buffers = .init(allocator),
            .images = .init(allocator),
            .render_passes = .init(allocator),
        };
    }

    pub fn deinit(self: @This()) void {
        self.buffers.deinit();
        self.images.deinit();
        self.render_passes.deinit();
    }
};
