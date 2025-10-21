const std = @import("std");

const vk = @import("vulkan");

const Window = @import("../../platform/sdl3.zig").Window;
const Backend = @import("backend.zig");
const BufferHandle = Backend.BufferHandle;
const ImageHandle = Backend.ImageHandle;
const GpuAllocator = @import("gpu_allocator.zig");

const BufferInterface = @import("buffer.zig").Interface;
const ImageInterface = @import("image.zig").Interface;

pub const QueueType = enum {
    graphics,
    prefer_async_compute,
    prefer_async_transfer,
};

pub fn SliceUploadFn(comptime T: type) type {
    return struct {
        pub fn uploadFn(data: ?*const anyopaque, data_len: ?usize, dst: []u8) usize {
            const temp_slice_ptr: [*]const T = @ptrCast(@alignCast(data.?));
            const temp_slice = temp_slice_ptr[0..data_len.?];
            const temp_slice_byte: []const u8 = std.mem.sliceAsBytes(temp_slice);
            @memcpy(dst[0..temp_slice_byte.len], temp_slice_byte);
            return temp_slice_byte.len;
        }
    };
}

/// Function should returns amount of data actually written
pub const UploadFn = *const fn (data: ?*const anyopaque, data_len: ?usize, dst: []u8) usize;

pub const DownloadFn = *const fn (data: ?*anyopaque, src: []u8) void;

pub const Resources = struct {
    buffers: []const BufferInterface,
    textures: []const ImageInterface,
};

pub const CommandBufferBuildFn = *const fn (
    data: ?*anyopaque,
    device: *Backend,
    resources: Resources,
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
pub const RenderGraphBufferHandle = struct { index: usize };

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
pub const RenderGraphTextureHandle = struct { index: usize };

pub const BufferUploadPass = struct {
    target: RenderGraphBufferHandle,
    offset: usize,
    size: usize,
    write_fn: UploadFn,
    write_data: ?*const anyopaque,
    write_data_len: ?usize,
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
                .color_attachments = .empty,
            };
        }
        try self.raster_pass.?.color_attachments.append(self.allocator, attachment);
    }

    pub fn addDepthAttachment(self: *Self, attachment: DepthAttachment) void {
        if (self.raster_pass == null) {
            self.raster_pass = RasterPass{
                .color_attachments = .empty,
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
            .swapchains = .empty,
            .transient_buffers = .empty,
            .transient_textures = .empty,
            .buffers = .empty,
            .textures = .empty,
            .buffer_upload_passes = .empty,
            .render_passes = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.swapchains.deinit(self.allocator);
        self.transient_buffers.deinit(self.allocator);
        self.transient_textures.deinit(self.allocator);
        self.buffers.deinit(self.allocator);
        self.textures.deinit(self.allocator);
        self.buffer_upload_passes.deinit(self.allocator);
        self.render_passes.deinit(self.allocator);
    }

    pub fn importBuffer(self: *Self, handle: BufferHandle) !RenderGraphBufferHandle {
        const buffer_index = self.buffers.items.len;
        try self.buffers.append(self.allocator, .{ .persistent = handle });
        return .{ .index = buffer_index };
    }

    pub fn createTransientBuffer(self: *Self, definition: TransientBuffer) !RenderGraphBufferHandle {
        const transient_index = self.transient_buffers.items.len;
        try self.transient_buffers.append(self.allocator, definition);

        const buffer_index = self.buffers.items.len;
        try self.buffers.append(self.allocator, .{ .transient = transient_index });
        return .{ .index = buffer_index };
    }

    pub fn importTexture(self: *Self, handle: ImageHandle) !RenderGraphTextureHandle {
        const texture_index = self.textures.items.len;
        try self.textures.append(self.allocator, .{ .persistent = handle });
        return .{ .index = texture_index };
    }

    pub fn createTransientTexture(self: *Self, definition: TransientTexture) !RenderGraphTextureHandle {
        const transient_index = self.transient_textures.items.len;
        try self.transient_textures.append(self.allocator, definition);

        const texture_index = self.textures.items.len;
        try self.textures.append(self.allocator, .{ .transient = transient_index });
        return .{ .index = texture_index };
    }

    pub fn acquireSwapchainTexture(self: *Self, window: Window) !RenderGraphTextureHandle {
        const swapchain_index = self.swapchains.items.len;
        try self.swapchains.append(self.allocator, window);

        const texture_index = self.textures.items.len;
        try self.textures.append(self.allocator, .{ .swapchain = swapchain_index });
        return .{ .index = texture_index };
    }

    pub fn uploadSliceToBuffer(render_graph: *Self, comptime T: type, usage: vk.BufferUsageFlags, slice: []const T) !RenderGraphBufferHandle {
        var temp_usage = usage;
        temp_usage.transfer_dst_bit = true;
        const temp_buffer_size: usize = @sizeOf(T) * slice.len;
        const temp_buffer = try render_graph.createTransientBuffer(.{
            .location = .gpu_only,
            .size = temp_buffer_size,
            .usage = temp_usage,
        });

        try render_graph.buffer_upload_passes.append(render_graph.allocator, .{
            .target = temp_buffer,
            .offset = 0,
            .size = temp_buffer_size,
            .write_data = @ptrCast(slice.ptr),
            .write_data_len = slice.len,
            .write_fn = SliceUploadFn(T).uploadFn,
        });

        return temp_buffer;
    }
};
