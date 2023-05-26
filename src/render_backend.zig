pub const RenderDeviceInitError = error{
    WhatErrorsCouldGoHere,
};

pub const Handle = struct {
    index: u32,
    generation: u32,
};

pub const ResourceHandle = union(enum) {
    persistent: Handle,
    transient: u32,
};

pub const SurfaceHandle = Handle;

pub const BufferHandle = ResourceHandle;
pub const TextureHandle = ResourceHandle;

pub const SamplerHandle = Handle;
pub const ComputePipelineHandle = Handle;
pub const RasterPipelineHandle = Handle;

pub const ResourceType = enum {
    Persistent,
    Transient,
};

pub const Queue = enum {
    Primary,
    PreferAsyncCompute,
    PreferAsyncTransfer,
};

pub const Transfer = struct {};

pub const ComputeDispatch = union(enum) {
    fixed: [3]u32,
    indirect: struct { buffer: BufferHandle, offset: usize },
};

pub const RasterCommand = union(enum) {
    bind_pipeline: RasterPipelineHandle,
};

pub const RenderDevice = struct {
    const Self = @This();

    pub fn init() RenderDeviceInitError!Self {
        return RenderDeviceInitError.WhatErrorsCouldGoHere;
    }

    pub fn create_buffer(self: *Self, name: []const u8, resource_type: ResourceType, size: usize) !BufferHandle {
        _ = self;
        _ = name;
        _ = resource_type;
        _ = size;
        return .{ .persistent = .{ .index = 0, .generation = 0 } };
    }
    pub fn destroy_buffer(self: *Self, handle: BufferHandle) void {
        _ = self;
        _ = handle;
    }

    pub fn create_texture(self: *Self, name: []const u8, resource_type: ResourceType, size: [2]u32) !TextureHandle {
        _ = self;
        _ = name;
        _ = resource_type;
        _ = size;
        return .{ .persistent = .{ .index = 0, .generation = 0 } };
    }
    pub fn destroy_texture(self: *Self, handle: TextureHandle) void {
        _ = self;
        _ = handle;
    }

    pub fn create_sampler(self: *Self, name: []const u8) !SamplerHandle {
        _ = self;
        _ = name;
        return .{ .index = 0, .generation = 0 };
    }
    pub fn destroy_sampler(self: *Self, handle: SamplerHandle) void {
        _ = self;
        _ = handle;
    }

    pub fn create_compute_pipeline(self: *Self, name: []const u8) !ComputePipelineHandle {
        _ = self;
        _ = name;
        return .{ .index = 0, .generation = 0 };
    }
    pub fn destroy_compute_pipeline(self: *Self, handle: ComputePipelineHandle) void {
        _ = self;
        _ = handle;
    }

    pub fn create_raster_pipeline(self: *Self, name: []const u8) !RasterPipelineHandle {
        _ = self;
        _ = name;
        return .{ .index = 0, .generation = 0 };
    }
    pub fn destroy_raster_pipeline(self: *Self, handle: RasterPipelineHandle) void {
        _ = self;
        _ = handle;
    }

    pub fn configure_surface(self: *Self, handle: SurfaceHandle, config: struct {}) !void {
        _ = self;
        _ = handle;
        _ = config;
    }
    pub fn destory_surface(self: *Self, handle: SurfaceHandle) void {
        _ = self;
        _ = handle;
    }

    //Rendering Functions
    pub fn acquire_surface_texture(self: *Self, handle: SurfaceHandle) TextureHandle {
        _ = self;
        _ = handle;
        return .{ .transient = 0 };
    }
    pub fn add_transfer_pass(self: *Self, name: []const u8, queue: Queue, transfers: []const Transfer) void {
        _ = self;
        _ = name;
        _ = queue;
        _ = transfers;
    }
    pub fn add_compute_pass(self: *Self, name: []const u8, queue: Queue, handle: ComputePipelineHandle, dipatch_size: ComputeDispatch) void {
        _ = self;
        _ = name;
        _ = queue;
        _ = handle;
        _ = dipatch_size;
    }
    pub fn add_raster_pass(self: *Self, name: []const u8, framebuffer_description: struct {}, raster_commands: []const RasterCommand) void {
        _ = self;
        _ = name;
        _ = framebuffer_description;
        _ = raster_commands;
    }
    pub fn submit_frame(self: *Self) !void {
        _ = self;
    }
};
