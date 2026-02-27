const std = @import("std");

const SdlPlatform = @import("platform2/sdl3.zig");

// ----------------------------
// Root Functions
// ----------------------------

var global_state: ?struct {
    gpa: std.mem.Allocator,
    platform: *SdlPlatform,
} = null;

pub fn init(gpa: std.mem.Allocator, desc: PlatformDesc) Error!PlatformInterface {
    std.debug.assert(global_state == null);

    const platform = try gpa.create(SdlPlatform);
    errdefer gpa.destroy(platform);

    platform.* = try .init(gpa, desc);
    errdefer platform.deinit();

    global_state = .{
        .gpa = gpa,
        .platform = platform,
    };

    return platform.interface();
}

pub fn deinit() void {
    if (global_state) |state| {
        state.platform.deinit();
        state.gpa.destroy(state.platform);
        global_state = null;
    }
}

// ----------------------------
// Platform Types
// ----------------------------

pub const Error = error{
    Unknown,

    OutOfMemory,
    OutOfDeviceMemory,

    InitializationFailed,
    FailedToInitPlatform,
    FailedToInitRenderingBackend,
    FailedToCreateWindow,
    FailedToCreateSurface,
    NoSuitableDeviceFound,
    ExtensionNotSupported,
    FeatureNotSupported,

    DeviceLost,
    WindowLost,

    InvalidUsage,
};

pub const Version = packed struct(u32) {
    patch: u12 = 0,
    minor: u10 = 0,
    major: u7 = 0,
    variant: u3 = 0,

    pub fn init(patch: u12, minor: u10, major: u7, variant: u3) @This() {
        return .{ .patch = patch, .major = major, .minor = minor, .variant = variant };
    }

    pub fn toU32(self: @This()) u32 {
        return @bitCast(self);
    }
};

pub const AppInfo = struct {
    name: []const u8,
    version: Version,
};

pub const RenderingBackend = enum {
    vulkan,
    dx12,
    metal,
};

pub const PlatformDesc = struct {
    app_info: AppInfo,
    force_rendering_backend: ?RenderingBackend = null,
    validation: bool = false,
};

pub const PlatformCallbacks = struct {
    ctx: ?*anyopaque = null,

    // App Callbacks
    quit: ?*const fn (ctx: ?*anyopaque) void = null,

    // Window Callbacks
    window_resize: ?*const fn (ctx: ?*anyopaque, window_handle: WindowHandle, size: [2]u32) void = null,
    window_close_requested: ?*const fn (ctx: ?*anyopaque, window_handle: WindowHandle) void = null,

    // Mouse Callbacks
    mouse_button: ?*const fn (ctx: ?*anyopaque, button: MouseButton, state: ButtonState) void = null,
    mouse_motion: ?*const fn (ctx: ?*anyopaque, position: [2]f32) void = null,
    mouse_wheel: ?*const fn (ctx: ?*anyopaque, delta: [2]i32) void = null,

    // Keyboard Callbacks
    text_input: ?*const fn (ctx: ?*anyopaque, text: []const u8) void = null,

    // Gamepad Callbacks
    gamepad_connected: ?*const fn (ctx: ?*anyopaque, gamepad_id: u32) void = null,
    gamepad_disconnected: ?*const fn (ctx: ?*anyopaque, gamepad_id: u32) void = null,
    gamepad_button: ?*const fn (ctx: ?*anyopaque, gamepad_id: u32, button: GamepadButton, state: ButtonState) void = null,
    gamepad_axis: ?*const fn (ctx: ?*anyopaque, gamepad_id: u32, axis: GamepadAxis, value: f32) void = null,
};

pub const PlatformInterface = struct {
    const Self = @This();

    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        // App
        process_events: *const fn (ctx: *anyopaque, callbacks: PlatformCallbacks) void,

        // Window
        createWindow: *const fn (ctx: *anyopaque, settings: WindowDesc) Error!WindowHandle,
        destroyWindow: *const fn (ctx: *anyopaque, window_handle: WindowHandle) void,
        getWindowSize: *const fn (ctx: *anyopaque, window_handle: WindowHandle) [2]u32,

        // Gpu Devices
        getDevices: *const fn (ctx: *anyopaque) []const DeviceInfo,
        doesDeviceSupportPresent: *const fn (ctx: *anyopaque, physical_device_index: u32, window_handle: WindowHandle) bool,
        getWindowSupport: *const fn (ctx: *anyopaque, physical_device_index: u32, window_handle: WindowHandle) ?WindowSurfaceInfo,
        createDevice: *const fn (ctx: *anyopaque, physical_device_index: u32, desc: DeviceDesc) Error!DeviceInterface,
        destroyDevice: *const fn (ctx: *anyopaque, device_interface: DeviceInterface) void,
    };

    // Convenience wrappers

    pub fn processEvents(self: *const Self, callbacks: PlatformCallbacks) void {
        self.vtable.process_events(self.ctx, callbacks);
    }

    pub fn createWindow(self: *const Self, settings: WindowDesc) Error!WindowHandle {
        return self.vtable.createWindow(self.ctx, settings);
    }

    pub fn destroyWindow(self: *const Self, window_handle: WindowHandle) void {
        self.vtable.destroyWindow(self.ctx, window_handle);
    }

    pub fn getWindowSize(self: *const Self, window_handle: WindowHandle) [2]u32 {
        return self.vtable.getWindowSize(self.ctx, window_handle);
    }

    pub fn createDeviceBasic(self: *const Self, window_opt: ?WindowHandle, power_level: DevicePowerPreference) Error!DeviceInterface {
        const SelectedDevice = struct {
            score: usize,
            info: DeviceInfo,
        };

        const prefered_type: DeviceType = switch (power_level) {
            .prefer_low_power => .integrated,
            .prefer_high_power => .discrete,
        };

        const devices = self.vtable.getDevices(self.ctx);
        var selected_device_opt: ?SelectedDevice = null;

        for (devices) |device_info| {
            if (window_opt) |window_handle| {
                if (!self.vtable.doesDeviceSupportPresent(self.ctx, device_info.physical_device_index, window_handle)) {
                    continue;
                }
            }

            const new_device: SelectedDevice = .{
                .info = device_info,
                .score = if (device_info.type == prefered_type) 100 else 1,
            };

            if (selected_device_opt) |*selected_device| {
                if (new_device.score > selected_device.score) {
                    selected_device.* = new_device;
                }
            } else {
                selected_device_opt = new_device;
            }
        }

        const selected_device = selected_device_opt orelse return error.NoSuitableDeviceFound;
        const device_interface: DeviceInterface = self.vtable.createDevice(
            self.ctx,
            selected_device.info.physical_device_index,
            .{
                .frames_in_flight = if (selected_device.info.type == .discrete) 3 else 2,
                .queues = selected_device.info.queues,
                .features = selected_device.info.features,
            },
        ) catch |err| return err;
        return device_interface;
    }

    pub fn destroyDevice(self: *const Self, device_interface: DeviceInterface) void {
        self.vtable.destroyDevice(self.ctx, device_interface);
    }
};

pub const WindowHandle = enum(u64) { null_handle = 0, _ };

pub const WindowSize = union(enum) {
    windowed: [2]i32,
    fullscreen,
    maximized,
};

pub const WindowDesc = struct {
    name: [*c]const u8,
    size: WindowSize,
    resizeable: bool,
};

pub const PresentMode = enum {
    fifo,
    immediate,
    mailbox,
};

pub const WindowSurfaceInfo = struct {
    min_image_count: u32,
    max_image_count: u32,
    usage: TextureUsage,
    formats: []const TextureFormat,
    present_modes: []const PresentMode,
};

pub const WindowSettings = struct {
    texture_count: u32,
    texture_usage: TextureUsage,
    texture_format: TextureFormat,
    present_mode: PresentMode,
};

pub const ButtonState = enum(u1) {
    pressed,
    released,
};

pub const MouseButton = enum(u8) {
    left = 1,
    middle = 2,
    right = 3,
    x1 = 4,
    x2 = 5,
};

pub const Keyboard = struct {};

pub const GamepadHandle = enum(u32) { null_handle = 0, _ };

pub const GamepadButton = enum(u8) {
    south = 0, // A on Xbox, Cross on PlayStation
    east = 1, // B on Xbox, Circle on PlayStation
    west = 2, // X on Xbox, Square on PlayStation
    north = 3, // Y on Xbox, Triangle on PlayStation
    back = 4,
    guide = 5,
    start = 6,
    left_stick = 7,
    right_stick = 8,
    left_shoulder = 9,
    right_shoulder = 10,
    dpad_up = 11,
    dpad_down = 12,
    dpad_left = 13,
    dpad_right = 14,
    trackpad = 20,
};

pub const GamepadAxis = enum(u8) {
    left_x = 0,
    left_y = 1,
    right_x = 2,
    right_y = 3,
    left_trigger = 4,
    right_trigger = 5,
};

pub const MemoryType = enum {
    gpu_only,
    cpu_to_gpu,
    gpu_to_cpu,
};

// ----------------------------
// Buffer Types
// ----------------------------

pub const BufferHandle = enum(u64) { null_handle = 0, _ };

pub const BufferDesc = struct {
    name: [:0]const u8,
    size: usize,
    usage: BufferUsage,
    memory: MemoryType,
};

pub const BufferUsage = struct {
    vertex: bool = false,
    index: bool = false,
    uniform: bool = false,
    storage: bool = false,
    device_address: bool = false,
    transfer_src: bool = false,
    transfer_dst: bool = false,
};

pub const BufferInfo = struct {
    size: usize,
    usage: BufferUsage,
    memory: MemoryType,

    mapped_slice: ?[]u8 = null,
    device_address: ?u64 = null,
    uniform: ?u32 = null,
    storage: ?u32 = null,
};

pub const TextureHandle = enum(u64) { null_handle = 0, _ };

pub const TextureDesc = struct {
    name: [:0]const u8,
    extent: TextureExtent,
    format: TextureFormat,
    mip_levels: u32 = 1,
    usage: TextureUsage,
    memory: MemoryType,
    sampler: SamplerHandle = .null_handle,
};

pub const TextureExtent = struct {
    width: u32,
    height: u32,
    depth: u32 = 1,
};

pub const TextureFormat = enum {
    rgba8_unorm,
    rgba8_srgb,
    bgra8_unorm,
    bgra8_srgb,

    rgba16_float,

    bc1_rgba_unorm,
    bc1_rgba_srgb,

    bc2_rgba_unorm,
    bc2_rgba_srgb,

    bc3_rgba_unorm,
    bc3_rgba_srgb,

    bc4_r_unorm,
    bc4_r_snorm,

    bc5_rg_unorm,
    bc5_rg_snorm,

    bc6h_rgb_ufloat,
    bc6h_rgb_sfloat,

    bc7_rgba_unorm,
    bc7_rgba_srgb,

    depth32_float,

    pub fn isColor(self: TextureFormat) bool {
        return switch (self) {
            .depth32_float => false,
            else => true,
        };
    }
};

pub const TextureUsage = struct {
    sampled: bool = false,
    storage: bool = false,
    attachment: bool = false,
    transfer: bool = false,
    host_transfer: bool = false,
};

pub const TextureInfo = struct {
    extent: TextureExtent,
    mip_levels: u32 = 1,
    format: TextureFormat,
    usage: TextureUsage,
    memory: MemoryType,

    sampled: ?u32 = null,
    storage: ?u32 = null,
};

pub const SamplerHandle = enum(u64) { null_handle = 0, _ };
pub const SamplerDesc = struct {};

// ----------------------------
// Pipline Types
// ----------------------------

pub const IndexType = enum {
    u16,
    u32,
};

pub const ShaderHandle = enum(u64) { null_handle = 0, _ };

pub const ShaderStage = enum {
    vertex,
    fragment,
    compute,
    task,
    mesh,
};

pub const ShaderDesc = struct {
    code: []const u32,
};

pub const GraphicsPipelineHandle = enum(u64) { null_handle = 0, _ };

pub const PrimitiveTopology = enum {
    triangle_list,
    triangle_strip,
    line_list,
};

pub const VertexInputRate = enum {
    vertex,
    instance,
};

pub const VertexBinding = struct {
    binding: u32,
    stride: u32,
    input_rate: VertexInputRate,
};

pub const VertexFormat = enum {
    float,
    float2,
    float3,
    float4,

    int,
    int2,
    int3,
    int4,

    uint,
    uint2,
    uint3,
    uint4,

    u8x4_norm,
    i8x4_norm,
    u16x2_norm,
    u16x4_norm,
};

pub const VertexAttribute = struct {
    binding: u32,
    location: u32,
    format: VertexFormat,
    offset: u32,
};

pub const VertexInputState = struct {
    bindings: []const VertexBinding = &.{},
    attributes: []const VertexAttribute = &.{},
};

pub const FillMode = enum {
    solid,
    wireframe,
};

pub const CullMode = enum {
    none,
    front,
    back,
    all,
};

pub const FrontFace = enum {
    clockwise,
    counter_clockwise,
};

pub const RasterizerState = struct {
    fill_mode: FillMode = .solid,
    cull_mode: CullMode = .none,
    front_face: FrontFace = .counter_clockwise,
    depth_bias_enable: bool = false,
    depth_bias_constant_factor: f32 = 0.0,
    depth_bias_clamp: f32 = 0.0,
    depth_bias_slope_factor: f32 = 0.0,
};

pub const CompareOp = enum(u8) {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,
};

pub const DepthStencilState = struct {
    depth_test_enable: bool = false,
    depth_write_enable: bool = false,
    depth_compare_op: CompareOp = .never,
    // stencil_test_enable: bool,
    // front: StencilFaceState,
    // back: StencilFaceState,
};

pub const RenderTargetInfo = struct {
    color_targets: []const TextureFormat = &.{},
    depth_target: ?TextureFormat = null,
    // stencil_target: ?TextureFormat = null,
};

pub const GraphicsPipelineDesc = struct {
    name: [:0]const u8,
    vertex: ShaderHandle,
    fragment: ?ShaderHandle = null,
    vertex_input_state: VertexInputState = .{},
    primitive_topology: PrimitiveTopology = .triangle_list,
    raster_state: RasterizerState = .{},
    depth_stencil_state: DepthStencilState = .{},
    target_info: RenderTargetInfo = .{},
};

pub const ComputePipelineHandle = enum(u64) { null_handle = 0, _ };
pub const ComputePipelineDesc = struct {
    name: [:0]const u8,
    shader: ShaderHandle,
};

// ----------------------------
// Device Types
// ----------------------------

pub const DevicePowerPreference = enum {
    prefer_low_power,
    prefer_high_power,
};

pub const DeviceDesc = struct {
    frames_in_flight: u32,
    queues: DeviceQueues,
    features: DeviceFeatures,
};

pub const DeviceType = enum {
    unknown,
    integrated,
    discrete,
    virtual,
    cpu,
};

// List from here: https://www.reddit.com/r/vulkan/comments/4ta9nj/is_there_a_comprehensive_list_of_the_names_and/
//TODO: find a more complete list?
pub const DeviceVendorID = enum(u32) {
    AMD = 0x1002,
    ImgTec = 0x1010,
    Nvidia = 0x10DE,
    ARM = 0x13B5,
    Qualcomm = 0x5143,
    Intel = 0x8086,
    _,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        if (std.enums.tagName(@This(), self)) |tag_name| {
            return writer.print("{s}", .{tag_name});
        } else {
            return writer.print("0x{x}", .{@intFromEnum(self)});
        }
    }
};

pub const DeviceQueues = struct {
    graphics: bool,
    async_compute: bool,
    async_transfer: bool,
};

pub const DeviceFeatures = struct {
    mesh_shading: bool,
    ray_tracing: bool,
    host_image_copy: bool,
    unified_image_layouts: bool,
};

pub const DeviceMemory = struct {
    // Bytes of GPU local (VRAM) memory
    device_local: u64,

    // CPU visible GPU memory
    device_local_host_visible: u64,

    // GPU visible CPU memory
    host_local: u64,

    // Unified memory flag for IGPUs, or DGPUs with all device-local memory mappabled
    unified_memory: bool,
};

pub const DeviceInfo = struct {
    physical_device_index: u32,
    name: []const u8,
    device_id: u32, // PCI device ID
    vendor_id: DeviceVendorID, // PCI vendor ID
    driver_version: u32,
    type: DeviceType,
    backend: RenderingBackend,

    queues: DeviceQueues,
    memory: DeviceMemory,
    features: DeviceFeatures,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        try writer.print(".{{\n", .{});
        try writer.print("  .physical_device_index = {},\n", .{self.physical_device_index});
        try writer.print("  .name = \"{s}\",\n", .{self.name});
        try writer.print("  .device_id = 0x{X},\n", .{self.device_id});
        try writer.print("  .vendor_id = .{f},\n", .{self.vendor_id});
        try writer.print("  .driver_version = 0x{X},\n", .{self.driver_version});
        try writer.print("  .type = .{s},\n", .{@tagName(self.type)});
        try writer.print("  .backend = .{s},\n", .{@tagName(self.backend)});
        try writer.print("  .queues = {},\n", .{self.queues});
        try writer.print("  .memory = {},\n", .{self.memory});
        try writer.print("  .features = {},\n", .{self.features});
        try writer.print("}}", .{});
    }
};

pub const DeviceInterface = struct {
    const Self = @This();

    // Opaque pointer to backend implementation
    ctx: *anyopaque,

    // V-table: function pointers to backend
    vtable: *const VTable,

    pub const VTable = struct {
        getInfo: *const fn (ctx: *anyopaque) DeviceInfo,

        createBuffer: *const fn (ctx: *anyopaque, desc: BufferDesc) Error!BufferHandle,
        destroyBuffer: *const fn (ctx: *anyopaque, handle: BufferHandle) void,
        getBufferInfo: *const fn (ctx: *anyopaque, handle: BufferHandle) ?BufferInfo,

        createTexture: *const fn (ctx: *anyopaque, desc: TextureDesc) Error!TextureHandle,
        destroyTexture: *const fn (ctx: *anyopaque, handle: TextureHandle) void,
        getTextureInfo: *const fn (ctx: *anyopaque, handle: TextureHandle) ?TextureInfo,

        canUploadTexture: *const fn (ctx: *anyopaque, handle: TextureHandle) bool,
        uploadTexture: *const fn (ctx: *anyopaque, handle: TextureHandle, mip_level: u32, data: []const u8) Error!void,

        createShaderModule: *const fn (ctx: *anyopaque, desc: ShaderDesc) Error!ShaderHandle,
        destroyShaderModule: *const fn (ctx: *anyopaque, handle: ShaderHandle) void,

        createGraphicsPipeline: *const fn (ctx: *anyopaque, desc: *const GraphicsPipelineDesc) Error!GraphicsPipelineHandle,
        destroyGraphicsPipeline: *const fn (ctx: *anyopaque, handle: GraphicsPipelineHandle) void,

        createComputePipeline: *const fn (ctx: *anyopaque, desc: ComputePipelineDesc) Error!ComputePipelineHandle,
        destroyComputePipeline: *const fn (ctx: *anyopaque, handle: ComputePipelineHandle) void,

        claimWindow: *const fn (ctx: *anyopaque, window_handle: WindowHandle, settings: WindowSettings) Error!void,
        releaseWindow: *const fn (ctx: *anyopaque, window_handle: WindowHandle) void,

        submit: *const fn (ctx: *anyopaque, tpa: std.mem.Allocator, graph: *const RenderGraph) Error!void,
        waitIdle: *const fn (ctx: *anyopaque) void,
    };

    pub fn getInfo(self: *const Self) DeviceInfo {
        return self.vtable.getInfo(self.ctx);
    }

    pub fn createBuffer(self: *const Self, desc: BufferDesc) Error!BufferHandle {
        return self.vtable.createBuffer(self.ctx, desc);
    }

    pub fn destroyBuffer(self: *const Self, handle: BufferHandle) void {
        self.vtable.destroyBuffer(self.ctx, handle);
    }

    pub fn getBufferInfo(self: *const Self, handle: BufferHandle) ?BufferInfo {
        self.vtable.getBufferInfo(self.ctx, handle);
    }

    pub fn createTexture(self: *const Self, desc: TextureDesc) Error!TextureHandle {
        return self.vtable.createTexture(self.ctx, desc);
    }

    pub fn destroyTexture(self: *const Self, handle: TextureHandle) void {
        self.vtable.destroyTexture(self.ctx, handle);
    }

    pub fn getTextureInfo(self: *const Self, handle: TextureHandle) ?TextureInfo {
        self.vtable.getTextureInfo(self.ctx, handle);
    }

    pub fn canUploadTexture(self: *const Self, handle: TextureHandle) bool {
        return self.vtable.canUploadTexture(self.ctx, handle);
    }

    pub fn uploadTexture(self: *const Self, handle: TextureHandle, mip_level: u32, data: []const u8) Error!void {
        return self.vtable.uploadTexture(self.ctx, handle, mip_level, data);
    }

    pub fn createShaderModule(self: *const Self, desc: ShaderDesc) Error!ShaderHandle {
        return self.vtable.createShaderModule(self.ctx, desc);
    }

    pub fn destroyShaderModule(self: *const Self, handle: ShaderHandle) void {
        self.vtable.destroyShaderModule(self.ctx, handle);
    }

    pub fn createGraphicsPipeline(self: *const Self, desc: *const GraphicsPipelineDesc) Error!GraphicsPipelineHandle {
        return self.vtable.createGraphicsPipeline(self.ctx, desc);
    }

    pub fn destroyGraphicsPipeline(self: *const Self, handle: GraphicsPipelineHandle) void {
        self.vtable.destroyGraphicsPipeline(self.ctx, handle);
    }

    pub fn createComputePipeline(self: *const Self, desc: ComputePipelineDesc) Error!ComputePipelineHandle {
        return self.vtable.createComputePipeline(self.ctx, desc);
    }

    pub fn destroyComputePipeline(self: *const Self, handle: ComputePipelineHandle) void {
        self.vtable.destroyComputePipeline(self.ctx, handle);
    }

    pub fn claimWindow(self: *const Self, window_handle: WindowHandle, settings: WindowSettings) Error!void {
        return self.vtable.claimWindow(self.ctx, window_handle, settings);
    }

    pub fn releaseWindow(self: *const Self, window_handle: WindowHandle) void {
        self.vtable.releaseWindow(self.ctx, window_handle);
    }

    pub fn submit(self: *const Self, tpa: std.mem.Allocator, graph: *const RenderGraph) Error!void {
        return self.vtable.submit(self.ctx, tpa, graph);
    }

    pub fn waitIdle(self: *const Self) void {
        self.vtable.waitIdle(self.ctx);
    }
};

// ----------------------------
// RenderGraph Types
// ----------------------------
pub const QueuePreference = enum {
    graphics,
    prefer_async_compute,
    prefer_async_transfer,
};

pub const RGBufferHandle = struct { idx: u32 };
pub const RGBufferDesc = struct {
    source: RGBufferSource,
    first_usage: ?RGPassHandle = null,
    last_usage: ?RGPassHandle = null,
};

pub const RGBufferUsage = struct {
    handle: RGBufferHandle,
    access: BufferAccess,
};
pub const RGBufferSource = union(enum) {
    persistent: BufferHandle,
    transient: usize,
};
pub const RGTransientBufferDesc = struct {
    size: usize,
    usage: BufferUsage,
    memory: MemoryType,
};

pub const RGTextureHandle = struct { idx: u32 };
pub const RGTextureDesc = struct {
    source: RGTextureSource,
    first_usage: ?RGPassHandle = null,
    last_usage: ?RGPassHandle = null,
};
pub const RGTextureUsage = struct {
    handle: RGTextureHandle,
    access: TextureAccess,
};
pub const RGTextureSource = union(enum) {
    persistent: TextureHandle,
    transient: usize,
    window: usize,
};
pub const RGTransientTextureDesc = struct {
    extent: RGTextureExtent,
    format: TextureFormat,
    mip_levels: u32 = 1,
    usage: TextureUsage,
    memory: MemoryType,
};
pub const RGWindowTextureDesc = struct {
    handle: WindowHandle,
    texture: RGTextureHandle,
};
pub const RGTextureExtent = union(enum) {
    fixed: [2]u32,
    relative: RGTextureHandle,
};

pub const BufferAccess = enum(u32) {
    none,
    vertex_read,
    index_read,
    indirect_read,

    compute_uniform_read,
    graphics_uniform_read,

    compute_storage_read,
    graphics_storage_read,

    compute_storage_write,
    graphics_storage_write,

    transfer_read,
    transfer_write,
};

pub const TextureAccess = enum(u32) {
    none,
    attachment_read,
    attachment_write,

    compute_sampled_read,
    graphics_sampled_read,

    compute_storage_read,
    graphics_storage_read,

    compute_storage_write,
    graphics_storage_write,

    transfer_read,
    transfer_write,
};

pub const RGColorAttachment = struct {
    texture: RGTextureHandle,
    clear: ?[4]f32,
};

pub const RGDepthAttachment = struct {
    texture: RGTextureHandle,
    clear: ?f32,
};

pub const RGRenderTarget = struct {
    color_attachments: []const RGColorAttachment = &.{},
    depth_attachment: ?RGDepthAttachment = null,
};

pub const RGPassCallback = union(enum) {
    transfer: struct {
        ctx: ?*anyopaque,
        func: TransferCommandEncoder.Callback,
    },
    compute: struct {
        ctx: ?*anyopaque,
        func: ComputeCommandEncoder.Callback,
    },
    graphics: struct {
        render_target: RGRenderTarget,
        ctx: ?*anyopaque,
        func: GraphicsCommandEncoder.Callback,
    },
};

pub const RGPassHandle = struct { idx: u32 };
pub const RGPassDesc = struct {
    handle: RGPassHandle,
    name: []const u8,
    queue: QueuePreference = .graphics,
    no_cull: bool = true,

    //TODO: store these as Hashmaps for faster fetch?
    //TODO: impl both and test perf
    buffer_usages: std.ArrayList(RGBufferUsage) = .empty,
    texture_usages: std.ArrayList(RGTextureUsage) = .empty,

    callback: ?RGPassCallback = null,

    pub fn getBufferAccess(self: *const RGPassDesc, handle: RGBufferHandle) ?BufferAccess {
        for (self.buffer_usages.items) |usage| {
            if (usage.handle.idx == handle.idx) {
                return usage.access;
            }
        }
        return null;
    }

    pub fn getTextureAccess(self: *const RGPassDesc, handle: RGTextureHandle) ?TextureAccess {
        for (self.texture_usages.items) |usage| {
            if (usage.handle.idx == handle.idx) {
                return usage.access;
            }
        }
        return null;
    }
};

pub const RenderGraph = struct {
    pub const Self = @This();

    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    window_textures: std.ArrayList(RGWindowTextureDesc) = .empty,
    transient_buffers: std.ArrayList(RGTransientBufferDesc) = .empty,
    transient_textures: std.ArrayList(RGTransientTextureDesc) = .empty,

    buffers: std.ArrayList(RGBufferDesc) = .empty,
    textures: std.ArrayList(RGTextureDesc) = .empty,

    passes: std.ArrayList(RGPassDesc) = .empty,

    pub fn init(gpa: std.mem.Allocator) Self {
        return .{ .gpa = gpa, .arena = .init(gpa) };
    }

    pub fn deinit(self: *Self) void {
        for (self.passes.items) |*pass| {
            self.gpa.free(pass.name);
            pass.buffer_usages.deinit(self.gpa);
            pass.texture_usages.deinit(self.gpa);

            if (pass.callback) |callback| {
                switch (callback) {
                    .graphics => |c| {
                        self.gpa.free(c.render_target.color_attachments);
                    },
                    else => {},
                }
            }
        }
        self.passes.deinit(self.gpa);
        self.textures.deinit(self.gpa);
        self.buffers.deinit(self.gpa);
        self.transient_textures.deinit(self.gpa);
        self.transient_buffers.deinit(self.gpa);
        self.window_textures.deinit(self.gpa);
        self.arena.deinit();
    }

    // Helper function for allocating data whos lifetime needs to match the RenderGraph
    // meant mostly for callback ctx's
    pub fn dupe(self: *Self, comptime T: type, value: T) error{OutOfMemory}!*T {
        const ptr = try self.arena.allocator().create(T);
        ptr.* = value;
        return ptr;
    }

    pub fn importBuffer(self: *Self, handle: BufferHandle) Error!RGBufferHandle {
        try self.buffers.append(self.gpa, .{ .source = .{ .persistent = handle } });
        return RGBufferHandle{ .idx = @intCast(self.buffers.items.len - 1) };
    }

    pub fn createTransientBuffer(self: *Self, desc: RGTransientBufferDesc) Error!RGBufferHandle {
        try self.transient_buffers.append(self.gpa, desc);
        const transient_idx = self.transient_buffers.items.len - 1;
        try self.buffers.append(self.gpa, .{ .source = .{ .transient = transient_idx } });
        return RGBufferHandle{ .idx = @intCast(self.buffers.items.len - 1) };
    }

    pub fn importTexture(self: *Self, handle: TextureHandle) Error!RGTextureHandle {
        try self.textures.append(self.gpa, .{ .source = .{ .persistent = handle } });
        return RGTextureHandle{ .idx = @intCast(self.textures.items.len - 1) };
    }

    pub fn createTransientTexture(self: *Self, desc: RGTransientTextureDesc) Error!RGTextureHandle {
        try self.transient_textures.append(self.gpa, desc);
        const transient_idx = self.transient_textures.items.len - 1;
        try self.textures.append(self.gpa, .{ .source = .{ .transient = transient_idx } });
        return RGTextureHandle{ .idx = @intCast(self.textures.items.len - 1) };
    }

    pub fn acquireWindowTexture(self: *Self, window: WindowHandle) Error!RGTextureHandle {
        const texture: RGTextureHandle = .{ .idx = @intCast(self.textures.items.len) };

        try self.window_textures.append(self.gpa, .{ .handle = window, .texture = texture });

        const window_idx = self.window_textures.items.len - 1;
        try self.textures.append(self.gpa, .{ .source = .{ .window = window_idx } });
        return texture;
    }

    pub fn addTransferPass(
        self: *Self,
        name: []const u8,
        ctx: ?*anyopaque,
        func: TransferCommandEncoder.Callback,
    ) Error!RGPassHandle {
        const handle = try self.createPass(name, .graphics);
        self.passes.items[handle.idx].callback = .{ .transfer = .{
            .ctx = ctx,
            .func = func,
        } };
        return handle;
    }

    pub fn addComputePass(
        self: *Self,
        name: []const u8,
        ctx: ?*anyopaque,
        func: ComputeCommandEncoder.Callback,
    ) Error!RGPassHandle {
        const handle = try self.createPass(name, .graphics);
        self.passes.items[handle.idx].callback = .{ .compute = .{
            .ctx = ctx,
            .func = func,
        } };
        return handle;
    }

    pub fn addGraphicsPass(
        self: *Self,
        name: []const u8,
        render_target: RGRenderTarget,
        ctx: ?*anyopaque,
        func: GraphicsCommandEncoder.Callback,
    ) Error!RGPassHandle {
        const handle = try self.createPass(name, .graphics);

        for (render_target.color_attachments) |attachment| {
            try self.addTextureUsage(handle, attachment.texture, .attachment_write);
        }

        if (render_target.depth_attachment) |attachment| {
            try self.addTextureUsage(handle, attachment.texture, .attachment_write);
        }

        self.passes.items[handle.idx].callback = .{ .graphics = .{
            .ctx = ctx,
            .func = func,
            .render_target = .{
                .color_attachments = try self.gpa.dupe(RGColorAttachment, render_target.color_attachments),
                .depth_attachment = render_target.depth_attachment,
            },
        } };
        return handle;
    }

    fn createPass(self: *Self, name: []const u8, queue: QueuePreference) Error!RGPassHandle {
        const handle = RGPassHandle{ .idx = @intCast(self.passes.items.len) };
        try self.passes.append(self.gpa, .{
            .handle = handle,
            .name = try self.gpa.dupe(u8, name),
            .queue = queue,
        });
        return handle;
    }

    pub fn addBufferUsage(self: *Self, pass: RGPassHandle, buffer: RGBufferHandle, access: BufferAccess) Error!void {
        try self.passes.items[pass.idx].buffer_usages.append(self.gpa, .{ .handle = buffer, .access = access });

        // Passes are guaranteed to be executed in the order of creatation
        // but usages can be added out of order, so we chose the smallest idx to be the first
        // and the largest idx to be the last

        const entry = &self.buffers.items[buffer.idx];
        if (entry.first_usage) |*usage| {
            usage.idx = @min(usage.idx, pass.idx);
        } else {
            entry.first_usage = pass;
        }
        if (entry.last_usage) |*usage| {
            usage.idx = @max(usage.idx, pass.idx);
        } else {
            entry.last_usage = pass;
        }
    }

    pub fn addTextureUsage(self: *Self, pass: RGPassHandle, texture: RGTextureHandle, access: TextureAccess) Error!void {
        try self.passes.items[pass.idx].texture_usages.append(self.gpa, .{ .handle = texture, .access = access });

        // Passes are guaranteed to be executed in the order of creatation
        // but usages can be added out of order, so we chose the smallest idx to be the first
        // and the largest idx to be the last

        const entry = &self.textures.items[texture.idx];
        if (entry.first_usage) |*usage| {
            usage.idx = @min(usage.idx, pass.idx);
        } else {
            entry.first_usage = pass;
        }
        if (entry.last_usage) |*usage| {
            usage.idx = @max(usage.idx, pass.idx);
        } else {
            entry.last_usage = pass;
        }
    }
};

pub const RenderGraphCompiled = struct {
    pub const Pass = struct {
        handle: RGPassHandle,
        first_usages: Dependencies = .empty,

        pass_dependencies: std.ArrayList(struct {
            pass: RGPassHandle,
            dependencies: Dependencies,
        }) = .empty,
    };

    pub const Resource = struct {
        access_count: usize = 0,
        first_sorted_access: ?usize = null,
        last_sorted_access: ?usize = null,
    };

    passes: std.ArrayList(Pass) = .empty,
    buffers: std.ArrayList(Resource) = .empty,
    textures: std.ArrayList(Resource) = .empty,

    pub fn deinit(self: *RenderGraphCompiled, gpa: std.mem.Allocator) void {
        for (self.passes.items) |*pass| {
            pass.first_usages.deinit(gpa);
            for (pass.pass_dependencies.items) |*pass_deps| {
                pass_deps.dependencies.deinit(gpa);
            }
            pass.pass_dependencies.deinit(gpa);
        }
        self.passes.deinit(gpa);
        self.buffers.deinit(gpa);
        self.textures.deinit(gpa);
    }

    pub fn compile(tpa: std.mem.Allocator, render_graph: *const RenderGraph) !RenderGraphCompiled {
        const last_buffer_access = try tpa.alloc(?RGPassHandle, render_graph.buffers.items.len);
        defer tpa.free(last_buffer_access);
        @memset(last_buffer_access, null);

        const last_texture_access = try tpa.alloc(?RGPassHandle, render_graph.textures.items.len);
        defer tpa.free(last_texture_access);
        @memset(last_texture_access, null);

        // Build graph
        var graph: RGDependencyGraph = .init(tpa);
        defer graph.deinit();

        for (render_graph.passes.items) |pass| {
            try graph.nodes.put(tpa, pass.handle, .{ .pass = pass.handle });

            for (pass.buffer_usages.items) |buffer_access| {
                try graph.addDependency(last_buffer_access[buffer_access.handle.idx], pass.handle, .{ .buffer = buffer_access.handle });
                last_buffer_access[buffer_access.handle.idx] = pass.handle;
            }

            for (pass.texture_usages.items) |texture_access| {
                try graph.addDependency(last_texture_access[texture_access.handle.idx], pass.handle, .{ .texture = texture_access.handle });
                last_texture_access[texture_access.handle.idx] = pass.handle;
            }
        }

        // Optimize Graph
        // TODO: eleminate read -> read barriers

        const reorder_graph: bool = true;

        var pass_execute_order: std.ArrayList(RGPassHandle) = try .initCapacity(tpa, render_graph.passes.items.len);
        defer pass_execute_order.deinit(tpa);

        // Topological Sort (kahn's algorithm)
        if (reorder_graph) {
            var node_degrees: std.ArrayList(struct {
                handle: RGPassHandle,
                in_degree: u32,
            }) = try .initCapacity(tpa, render_graph.passes.items.len);
            defer node_degrees.deinit(tpa);

            var q: std.ArrayList(RGPassHandle) = try .initCapacity(tpa, render_graph.passes.items.len);
            defer q.deinit(tpa);

            for (graph.nodes.values()) |node| {
                node_degrees.appendAssumeCapacity(.{
                    .handle = node.pass,
                    .in_degree = @intCast(node.pass_dependencies.count()),
                });
            }

            for (node_degrees.items) |node| {
                if (node.in_degree == 0) {
                    q.appendAssumeCapacity(node.handle);
                }
            }

            while (q.items.len > 0) {
                const top = q.orderedRemove(0);

                pass_execute_order.appendAssumeCapacity(top);

                for (graph.nodes.values(), node_degrees.items) |node, *node_degree| {
                    if (node_degree.in_degree != 0) {
                        if (node.pass_dependencies.contains(top)) {
                            node_degree.in_degree -= 1;

                            if (node_degree.in_degree == 0) {
                                q.appendAssumeCapacity(node.pass);
                            }
                        }
                    }
                }
            }
        } else {
            for (graph.nodes.values()) |node| {
                pass_execute_order.appendAssumeCapacity(node.pass);
            }
        }

        var result: RenderGraphCompiled = .{};
        errdefer result.deinit(tpa);

        result.buffers = try .initCapacity(tpa, render_graph.buffers.items.len);
        result.buffers.appendNTimesAssumeCapacity(.{}, result.buffers.capacity);

        result.textures = try .initCapacity(tpa, render_graph.textures.items.len);
        result.textures.appendNTimesAssumeCapacity(.{}, result.textures.capacity);

        for (pass_execute_order.items) |pass_handle| {
            if (graph.nodes.getPtr(pass_handle)) |node| {
                var result_pass: Pass = .{ .handle = pass_handle };
                result_pass.first_usages = try node.first_usages.clone(tpa);

                var iter = node.pass_dependencies.iterator();
                while (iter.next()) |entry| {
                    try result_pass.pass_dependencies.append(tpa, .{
                        .pass = entry.key_ptr.*,
                        .dependencies = try entry.value_ptr.clone(tpa),
                    });
                }

                try result.passes.append(tpa, result_pass);
            }
        }

        return result;
    }
};

pub const Dependency = union(enum) {
    buffer: RGBufferHandle,
    texture: RGTextureHandle,
};

pub const Dependencies = std.ArrayList(Dependency);

pub const RGNode = struct {
    pass: RGPassHandle,
    first_usages: Dependencies = .empty,
    pass_dependencies: std.AutoArrayHashMapUnmanaged(RGPassHandle, Dependencies) = .empty,

    pub fn init(pass: RGPassHandle) RGNode {
        return .{
            .pass = pass,
        };
    }

    pub fn deinit(self: *RGNode, gpa: std.mem.Allocator) void {
        self.first_usages.deinit(gpa);
        for (self.pass_dependencies.values()) |*dependencies| {
            dependencies.deinit(gpa);
        }
        self.pass_dependencies.deinit(gpa);
    }
};

pub const RGDependencyGraph = struct {
    gpa: std.mem.Allocator,
    nodes: std.AutoArrayHashMapUnmanaged(RGPassHandle, RGNode) = .empty,

    pub fn init(gpa: std.mem.Allocator) RGDependencyGraph {
        return .{
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *RGDependencyGraph) void {
        for (self.nodes.values()) |*node| {
            node.deinit(self.gpa);
        }
        self.nodes.deinit(self.gpa);
    }

    pub fn addNode(
        self: *RGDependencyGraph,
        pass: RGPassHandle,
    ) !void {
        try self.nodes.put(self.gpa, pass, .{ .pass = pass });
    }

    pub fn addDependency(self: *RGDependencyGraph, src_opt: ?RGPassHandle, dst: RGPassHandle, dependency: Dependency) !void {
        const dst_node = self.nodes.getPtr(dst).?;

        if (src_opt) |src| {
            if (!dst_node.pass_dependencies.contains(src)) {
                try dst_node.pass_dependencies.put(self.gpa, src, .empty);
            }
            const src_dependencies = dst_node.pass_dependencies.getPtr(src).?;
            try src_dependencies.append(self.gpa, dependency);
        } else {
            try dst_node.first_usages.append(self.gpa, dependency);
        }
    }
};

// ----------------------------
// Command Encoder Types
// ----------------------------

pub const BufferArg = union(enum) {
    tracked: RGBufferHandle,
    untracked: BufferHandle,

    pub fn from(buffer: anytype) BufferArg {
        const BufferType = @TypeOf(buffer);
        if (BufferType == RGBufferHandle) {
            return .{ .tracked = buffer };
        } else if (BufferType == BufferHandle) {
            return .{ .untracked = buffer };
        } else {
            @compileError("Unknown buffer type");
        }
    }
};

pub const TextureArg = union(enum) {
    tracked: RGTextureHandle,
    untracked: TextureHandle,

    pub fn from(buffer: anytype) BufferArg {
        const TextureType = @TypeOf(buffer);
        if (TextureType == RGTextureHandle) {
            return .{ .tracked = buffer };
        } else if (TextureType == TextureHandle) {
            return .{ .untracked = buffer };
        } else {
            @compileError("Unknown buffer type");
        }
    }
};

pub const BufferCopyRegion = struct {
    src_offset: u64 = 0,
    dst_offset: u64 = 0,
    size: u64,
};

pub const TextureCopyRegion = struct {
    src_mip_level: u32 = 0,
    dst_mip_level: u32 = 0,
    src_offset: [3]u32 = .{ 0, 0, 0 },
    dst_offset: [3]u32 = .{ 0, 0, 0 },
    extent: TextureExtent,
};

pub const BufferTextureCopyRegion = struct {
    buffer_offset: u64 = 0,
    buffer_row_length: u32 = 0,
    buffer_image_height: u32 = 0,
    texture_mip_level: u32 = 0,
    texture_offset: [3]u32 = .{ 0, 0, 0 },
    extent: TextureExtent,
};

pub const TransferCommandEncoder = struct {
    const Self = @This();

    pub const Callback = *const fn (data: ?*anyopaque, encoder: Self) void;

    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        getBufferInfo: *const fn (ctx: *anyopaque, handle: BufferArg) ?BufferInfo,
        getTextureInfo: *const fn (ctx: *anyopaque, handle: TextureArg) ?TextureInfo,

        updateBuffer: *const fn (ctx: *anyopaque, buffer: BufferArg, offset: u64, data: []const u8) void,
        copyBuffer: *const fn (ctx: *anyopaque, src: BufferArg, dst: BufferArg, regions: []const BufferCopyRegion) void,
        copyTexture: *const fn (ctx: *anyopaque, src: TextureArg, dst: TextureArg, regions: []const TextureCopyRegion) void,
        copyBufferToTexture: *const fn (ctx: *anyopaque, src: BufferArg, dst: TextureArg, regions: []const BufferTextureCopyRegion) void,
        copyTextureToBuffer: *const fn (ctx: *anyopaque, src: TextureArg, dst: BufferArg, regions: []const BufferTextureCopyRegion) void,
    };

    pub fn getBufferInfo(self: Self, handle: BufferArg) ?BufferInfo {
        return self.vtable.getBufferInfo(self.ctx, handle);
    }

    pub fn getTextureInfo(self: Self, handle: BufferArg) ?TextureInfo {
        return self.vtable.getTextureInfo(self.ctx, handle);
    }

    pub fn updateBuffer(self: Self, buffer: BufferArg, offset: u64, data: []const u8) void {
        self.vtable.updateBuffer(self.ctx, buffer, offset, data);
    }

    pub fn copyBuffer(self: Self, src: BufferArg, dst: BufferArg, regions: []const BufferCopyRegion) void {
        self.vtable.copyBuffer(self.ctx, src, dst, regions);
    }

    pub fn copyTexture(self: Self, src: TextureArg, dst: TextureArg, regions: []const TextureCopyRegion) void {
        self.vtable.copyTexture(self.ctx, src, dst, regions);
    }

    pub fn copyBufferToTexture(self: Self, src: BufferArg, dst: TextureArg, regions: []const BufferTextureCopyRegion) void {
        self.vtable.copyBufferToTexture(self.ctx, src, dst, regions);
    }

    pub fn copyTextureToBuffer(self: Self, src: TextureArg, dst: BufferAccess, regions: []const BufferTextureCopyRegion) void {
        self.vtable.copyTextureToBuffer(self.ctx, src, dst, regions);
    }
};

pub const IndirectDispatchCommand = extern struct {
    x: u32,
    y: u32,
    z: u32,
};

pub const ComputeCommandEncoder = struct {
    const Self = @This();

    pub const Callback = *const fn (data: ?*anyopaque, encoder: Self) void;

    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        getBufferInfo: *const fn (ctx: *anyopaque, handle: BufferArg) ?BufferInfo,
        getTextureInfo: *const fn (ctx: *anyopaque, handle: TextureArg) ?TextureInfo,
        pushConstantsRaw: *const fn (ctx: *anyopaque, data: []const u8) void,

        setPipeline: *const fn (ctx: *anyopaque, pipeline: ComputePipelineHandle) void,
        dispatch: *const fn (ctx: *anyopaque, x: u32, y: u32, z: u32) void,
        dispatchIndirect: *const fn (ctx: *anyopaque, buffer: BufferArg, offset: u64) void,
    };

    pub fn getBufferInfo(self: Self, handle: BufferArg) ?BufferInfo {
        return self.vtable.getBufferInfo(self.ctx, handle);
    }

    pub fn getTextureInfo(self: Self, handle: TextureArg) ?TextureInfo {
        return self.vtable.getTextureInfo(self.ctx, handle);
    }

    pub fn pushConstantsBytes(self: Self, data: []const u8) void {
        self.vtable.pushConstantsRaw(self.ctx, data);
    }

    pub fn pushConstants(self: Self, comptime T: type, value: T) void {
        self.vtable.pushConstantsRaw(self.ctx, std.mem.asBytes(&value));
    }

    pub fn pushConstantsSlice(self: Self, comptime T: type, slice: []const T) void {
        self.vtable.pushConstantsRaw(self.ctx, std.mem.sliceAsBytes(slice));
    }

    pub fn setPipeline(self: Self, pipeline: ComputePipelineHandle) void {
        self.vtable.setPipeline(self.ctx, pipeline);
    }

    pub fn dispatch(self: Self, x: u32, y: u32, z: u32) void {
        self.vtable.dispatch(self.ctx, x, y, z);
    }

    pub fn dispatchIndirect(self: Self, buffer: BufferArg, offset: u64) void {
        self.vtable.dispatchIndirect(self.ctx, buffer, offset);
    }
};

pub const Viewport = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32,
    height: f32,
    min_depth: f32 = 0.0,
    max_depth: f32 = 1.0,
};

pub const Rect2D = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: u32,
    height: u32,
};

pub const IndirectDrawCommand = extern struct {
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
};

pub const IndirectDrawIndexedCommand = extern struct {
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
};

pub const IndirectDrawMeshTasksCommand = extern struct {
    group_count_x: u32,
    group_count_y: u32,
    group_count_z: u32,
};

pub const GraphicsCommandEncoder = struct {
    const Self = @This();

    pub const Callback = *const fn (data: ?*anyopaque, encoder: Self) void;

    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        getBufferInfo: *const fn (ctx: *anyopaque, handle: BufferArg) ?BufferInfo,
        getTextureInfo: *const fn (ctx: *anyopaque, handle: TextureArg) ?TextureInfo,
        pushConstantsRaw: *const fn (ctx: *anyopaque, data: []const u8) void,

        setVertexBuffer: *const fn (ctx: *anyopaque, binding: u32, buffer: BufferArg, offset: u64) void,
        setIndexBuffer: *const fn (ctx: *anyopaque, buffer: BufferArg, index_type: IndexType, offset: u64) void,

        // Dynamic state
        setViewport: *const fn (ctx: *anyopaque, viewport: Viewport) void,
        setScissor: *const fn (ctx: *anyopaque, rect: Rect2D) void,

        setPipeline: *const fn (ctx: *anyopaque, pipeline: GraphicsPipelineHandle) void,

        draw: *const fn (ctx: *anyopaque, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void,
        drawIndirect: *const fn (ctx: *anyopaque, buffer: BufferArg, offset: u64, draw_count: u32, stride: u32) void,
        drawIndirectCount: *const fn (ctx: *anyopaque, buffer: BufferArg, offset: u64, count_buffer: BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void,

        drawIndexed: *const fn (ctx: *anyopaque, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void,
        drawIndexedIndirect: *const fn (ctx: *anyopaque, buffer: BufferArg, offset: u64, draw_count: u32, stride: u32) void,
        drawIndexedIndirectCount: *const fn (ctx: *anyopaque, buffer: BufferArg, offset: u64, count_buffer: BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void,

        drawMeshTasks: *const fn (ctx: *anyopaque, x: u32, y: u32, z: u32) void,
        drawMeshTasksIndirect: *const fn (ctx: *anyopaque, buffer: BufferArg, offset: u64, draw_count: u32, stride: u32) void,
        drawMeshTasksIndirectCount: *const fn (ctx: *anyopaque, buffer: BufferArg, offset: u64, count_buffer: BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void,
    };

    pub fn getBufferInfo(self: Self, handle: BufferArg) ?BufferInfo {
        return self.vtable.getBufferInfo(self.ctx, handle);
    }

    pub fn getTextureInfo(self: Self, handle: TextureArg) ?TextureInfo {
        return self.vtable.getTextureInfo(self.ctx, handle);
    }

    pub fn pushConstantsBytes(self: Self, data: []const u8) void {
        self.vtable.pushConstantsRaw(self.ctx, data);
    }

    pub fn pushConstants(self: Self, comptime T: type, value: T) void {
        self.vtable.pushConstantsRaw(self.ctx, std.mem.asBytes(&value));
    }

    pub fn pushConstantsSlice(self: Self, comptime T: type, slice: []const T) void {
        self.vtable.pushConstantsRaw(self.ctx, std.mem.sliceAsBytes(slice));
    }

    pub fn setVertexBuffer(self: Self, binding: u32, buffer: BufferArg, offset: u64) void {
        self.vtable.setVertexBuffer(self.ctx, binding, buffer, offset);
    }

    pub fn setIndexBuffer(self: Self, buffer: BufferArg, index_type: IndexType, offset: u64) void {
        self.vtable.setIndexBuffer(self.ctx, buffer, index_type, offset);
    }

    pub fn setViewport(self: Self, viewport: Viewport) void {
        self.vtable.setViewport(self.ctx, viewport);
    }

    pub fn setScissor(self: Self, rect: Rect2D) void {
        self.vtable.setScissor(self.ctx, rect);
    }

    pub fn setPipeline(self: Self, pipeline: GraphicsPipelineHandle) void {
        self.vtable.setPipeline(self.ctx, pipeline);
    }

    pub fn draw(self: Self, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        self.vtable.draw(self.ctx, vertex_count, instance_count, first_vertex, first_instance);
    }

    pub fn drawIndirect(self: Self, buffer: BufferArg, offset: u64, draw_count: u32, stride: u32) void {
        self.vtable.drawIndirect(self.ctx, buffer, offset, draw_count, stride);
    }

    pub fn drawIndirectCount(self: Self, buffer: BufferArg, offset: u64, count_buffer: BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void {
        self.vtable.drawIndirectCount(self.ctx, buffer, offset, count_buffer, count_offset, max_draw_count, stride);
    }

    pub fn drawIndexed(self: Self, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
        self.vtable.drawIndexed(self.ctx, index_count, instance_count, first_index, vertex_offset, first_instance);
    }

    pub fn drawIndexedIndirect(self: Self, buffer: BufferArg, offset: u64, draw_count: u32, stride: u32) void {
        self.vtable.drawIndexedIndirect(self.ctx, buffer, offset, draw_count, stride);
    }

    pub fn drawIndexedIndirectCount(self: Self, buffer: BufferArg, offset: u64, count_buffer: BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void {
        self.vtable.drawIndexedIndirectCount(self.ctx, buffer, offset, count_buffer, count_offset, max_draw_count, stride);
    }

    pub fn drawMeshTasks(self: Self, x: u32, y: u32, z: u32) void {
        self.vtable.drawMeshTasks(self.ctx, x, y, z);
    }

    pub fn drawMeshTasksIndirect(self: Self, buffer: BufferArg, offset: u64, draw_count: u32, stride: u32) void {
        self.vtable.drawMeshTasksIndirect(self.ctx, buffer, offset, draw_count, stride);
    }

    pub fn drawMeshTasksIndirectCount(self: Self, buffer: BufferArg, offset: u64, count_buffer: BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void {
        self.vtable.drawMeshTasksIndirectCount(self.ctx, buffer, offset, count_buffer, count_offset, max_draw_count, stride);
    }
};
