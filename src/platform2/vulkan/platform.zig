const std = @import("std");

const vk = @import("vulkan");

const saturn = @import("../../root.zig");

const Instance = @import("instance.zig");

const VkDevice = @import("device.zig");
const Swapchain = @import("swapchain.zig");
const object_pools = @import("object_pools.zig");
const Buffer = @import("buffer.zig");
const Texture = @import("texture.zig");
const Pipeline = @import("pipeline.zig");
const BindlessDescriptor = @import("bindless_descriptor.zig");
const render_graph_executor = @import("render_graph_executor.zig");

pub const SurfaceCreateFn = *const fn (instance: vk.Instance, window: saturn.WindowHandle, allocator: ?*const vk.AllocationCallbacks) ?vk.SurfaceKHR;
pub const GetWindowSizeFn = *const fn (window: saturn.WindowHandle, user_data: ?*anyopaque) [2]u32;

pub const Backend = struct {
    const Self = @This();

    gpa: std.mem.Allocator,

    instance: *Instance,

    create_surface_fn: SurfaceCreateFn,
    surfaces: std.AutoArrayHashMap(saturn.WindowHandle, vk.SurfaceKHR),

    devices: std.AutoHashMap(*Device, void),

    // Window size callback
    get_window_size_fn: GetWindowSizeFn,
    get_window_size_user_data: ?*anyopaque,

    pub fn init(
        gpa: std.mem.Allocator,
        loader: vk.PfnGetInstanceProcAddr,
        extensions: []const [*c]const u8,
        create_surface_fn: SurfaceCreateFn,
        get_window_size_fn: GetWindowSizeFn,
        get_window_size_user_data: ?*anyopaque,
        engine: saturn.AppInfo,
        app: saturn.AppInfo,
        validation: bool,
    ) saturn.Error!Self {
        const instance = try gpa.create(Instance);
        errdefer gpa.destroy(instance);

        const engine_name_z = try gpa.dupeZ(u8, engine.name);
        defer gpa.free(engine_name_z);

        const app_name_z = try gpa.dupeZ(u8, app.name);
        defer gpa.free(app_name_z);

        instance.* = Instance.init(
            gpa,
            loader,
            extensions,
            .{
                .p_engine_name = engine_name_z,
                .engine_version = engine.version.toU32(),
                .p_application_name = app_name_z,
                .application_version = app.version.toU32(),
                .api_version = @bitCast(vk.API_VERSION_1_3),
            },
            validation,
        ) catch return error.FailedToInitRenderingBackend;
        errdefer instance.deinit();

        return .{
            .gpa = gpa,
            .instance = instance,
            .create_surface_fn = create_surface_fn,
            .surfaces = .init(gpa),
            .devices = .init(gpa),
            .get_window_size_fn = get_window_size_fn,
            .get_window_size_user_data = get_window_size_user_data,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.devices.keyIterator();
        while (iter.next()) |device_ptr| {
            device_ptr.*.deinit();
            self.gpa.destroy(device_ptr.*);
        }
        self.devices.deinit();

        self.surfaces.deinit();
        self.instance.deinit();
        self.gpa.destroy(self.instance);
    }

    pub fn createSurface(self: *Self, window: saturn.WindowHandle) saturn.Error!void {
        const surface = self.create_surface_fn(self.instance.proxy.handle, window, null) orelse return error.FailedToCreateSurface;
        try self.surfaces.put(window, surface);
    }

    pub fn destroySurface(self: *Self, window: saturn.WindowHandle) void {
        if (self.surfaces.get(window)) |surface| {
            self.instance.proxy.destroySurfaceKHR(surface, null);
            _ = self.surfaces.swapRemove(window);
        }
    }

    pub fn doesDeviceSupportPresent(self: *Self, device_index: u32, window: saturn.WindowHandle) bool {
        if (self.surfaces.get(window)) |surface| {
            const result = self.instance.proxy.getPhysicalDeviceSurfaceSupportKHR(
                self.instance.physical_devices[device_index].handle,
                self.instance.physical_devices[device_index].info.queues.graphics.?,
                surface,
            ) catch return false;
            return result == .true;
        }

        return false;
    }

    pub fn createDevice(
        self: *Self,
        physical_device_index: u32,
        desc: saturn.DeviceDesc,
    ) saturn.Error!saturn.DeviceInterface {
        const device_ptr = try self.gpa.create(Device);
        errdefer self.gpa.destroy(device_ptr);

        device_ptr.* = try .init(
            self.gpa,
            self,
            physical_device_index,
            desc,
        );
        errdefer device_ptr.deinit();

        try self.devices.put(device_ptr, {});
        return device_ptr.interface();
    }

    pub fn destroyDevice(self: *Self, device: saturn.DeviceInterface) void {
        const device_ptr: *Device = @ptrCast(@alignCast(device.ctx));

        if (self.devices.remove(device_ptr)) {
            device.waitIdle();
            device_ptr.deinit();
            self.gpa.destroy(device_ptr);
        }
    }
};

pub const QueueFamily = enum {
    graphics,
    compute,
    transfer,
};

const BufferInfo = struct {
    buffer: Buffer,
    owner_queue: ?QueueFamily = null,
};

const TextureInfo = struct {
    texture: Texture,
    owner_queue: ?QueueFamily = null,
    layout: vk.ImageLayout = .undefined,
};

pub const Device = struct {
    pub const PerFrameData = struct {
        frame_wait_fences: std.ArrayList(vk.Fence) = .empty,
        graphics_command_pool: object_pools.CommandBufferPool,
        semaphore_pool: object_pools.SemaphorePool,
        fence_pool: object_pools.FencePool,

        buffer_access: std.AutoArrayHashMap(saturn.BufferHandle, saturn.BufferAccess),
        texture_access: std.AutoArrayHashMap(saturn.TextureHandle, saturn.TextureAccess),

        transient_buffers: std.ArrayList(Buffer) = .empty,
        transient_textures: std.ArrayList(Texture) = .empty,

        pub fn init(gpa: std.mem.Allocator, device: *VkDevice) !PerFrameData {
            return .{
                .graphics_command_pool = try .init(gpa, device, device.graphics_queue),
                .semaphore_pool = .init(gpa, device, .binary, 0),
                .fence_pool = .init(gpa, device, .{}),

                .buffer_access = .init(gpa),
                .texture_access = .init(gpa),
            };
        }

        pub fn deinit(self: *PerFrameData, gpa: std.mem.Allocator, device: *VkDevice) void {
            self.frame_wait_fences.deinit(gpa);
            self.graphics_command_pool.deinit();
            self.semaphore_pool.deinit();
            self.fence_pool.deinit();

            for (self.transient_buffers.items) |buffer| {
                buffer.deinit(device);
            }
            self.transient_buffers.deinit(gpa);

            for (self.transient_textures.items) |texture| {
                texture.deinit(device);
            }
            self.transient_textures.deinit(gpa);

            self.buffer_access.deinit();
            self.texture_access.deinit();
        }

        pub fn waitForPrevious(self: *@This(), device: vk.DeviceProxy, timeout_ns: u64) bool {
            if (self.frame_wait_fences.items.len > 0) {
                defer self.frame_wait_fences.clearRetainingCapacity();
                _ = device.waitForFences(@intCast(self.frame_wait_fences.items.len), self.frame_wait_fences.items.ptr, .true, timeout_ns) catch return false;
            }
            return true;
        }

        pub fn reset(self: *@This(), device: *VkDevice) void {
            self.frame_wait_fences.clearRetainingCapacity();
            self.graphics_command_pool.reset() catch |err| {
                //If this fails, well just allocate more buffers I guess ¯\_(ツ)_/¯
                std.log.err("Failed to reset command pool: {}", .{err});
            };
            self.semaphore_pool.reset();
            self.fence_pool.reset() catch |err| {
                //If this fails, IDK what to do ¯\_(ツ)_/¯
                std.log.err("Failed to reset fence pool: {}", .{err});
            };

            self.buffer_access.clearRetainingCapacity();
            self.texture_access.clearRetainingCapacity();

            for (self.transient_buffers.items) |buffer| {
                buffer.deinit(device);
            }
            self.transient_buffers.clearRetainingCapacity();

            for (self.transient_textures.items) |texture| {
                texture.deinit(device);
            }
            self.transient_textures.clearRetainingCapacity();
        }

        pub fn errorReset(self: *@This(), device: vk.DeviceProxy) void {
            if (self.frame_wait_fences.items.len > 0) {
                device.resetFences(@intCast(self.frame_wait_fences.items.len), self.frame_wait_fences.items.ptr) catch |err| {
                    std.log.err("Failed to reset frame_wait_fences: {}", .{err});
                };
                self.frame_wait_fences.clearRetainingCapacity();
            }
        }
    };

    const Self = @This();

    gpa: std.mem.Allocator,
    backend: *Backend,
    physical_device_index: u32,
    device: *VkDevice,

    pipeline_layout: vk.PipelineLayout,
    linear_sampler: vk.Sampler,

    swapchains: std.AutoHashMap(saturn.WindowHandle, *Swapchain),
    shader_modules: std.AutoHashMap(saturn.ShaderHandle, vk.ShaderModule),
    graphics_pipelines: std.AutoHashMap(saturn.GraphicsPipelineHandle, vk.Pipeline),
    compute_pipelines: std.AutoHashMap(saturn.ComputePipelineHandle, vk.Pipeline),
    buffers: std.AutoHashMap(saturn.BufferHandle, BufferInfo),
    textures: std.AutoHashMap(saturn.TextureHandle, TextureInfo),

    // Dynamic frames in flight
    frame_index: usize = 0,
    per_frame_data: []PerFrameData,

    submit_timeout_ns: u64 = std.time.ns_per_s * 5,

    pub fn init(
        gpa: std.mem.Allocator,
        backend: *Backend,
        physical_device_index: u32,
        desc: saturn.DeviceDesc,
    ) saturn.Error!Self {
        var device = try gpa.create(VkDevice);
        errdefer gpa.destroy(device);

        const physical_device = backend.instance.physical_devices[physical_device_index];

        if (desc.features.ray_tracing and !physical_device.info.extensions.ray_tracing) {
            return error.FeatureNotSupported;
        }

        if (desc.features.mesh_shading and !physical_device.info.extensions.mesh_shading) {
            return error.FeatureNotSupported;
        }

        if (desc.features.host_image_copy and !physical_device.info.extensions.host_image_copy) {
            return error.FeatureNotSupported;
        }

        device.* = VkDevice.init(
            gpa,
            backend.instance.proxy,
            physical_device,
            desc.features,
            backend.instance.debug_messager != null,
        ) catch |err| {
            return switch (err) {
                error.OutOfHostMemory => error.OutOfMemory,
                error.ExtensionNotPresent => error.ExtensionNotSupported,
                error.FeatureNotPresent => error.FeatureNotSupported,
                else => error.InitializationFailed,
            };
        };
        errdefer device.deinit();

        const descriptor_set_layouts: []const vk.DescriptorSetLayout = &.{device.descriptor.layout};
        const push_ranges: []const vk.PushConstantRange = &.{.{ .offset = 0, .size = 256, .stage_flags = device.all_stage_flags }};

        const pipeline_layout = device.proxy.createPipelineLayout(&.{
            .set_layout_count = @intCast(descriptor_set_layouts.len),
            .p_set_layouts = descriptor_set_layouts.ptr,
            .push_constant_range_count = @intCast(push_ranges.len),
            .p_push_constant_ranges = push_ranges.ptr,
        }, null) catch return error.InitializationFailed;
        errdefer device.proxy.destroyPipelineLayout(pipeline_layout, null);

        const linear_sampler = device.proxy.createSampler(&.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_mode = .nearest,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .mip_lod_bias = 0.0,
            .anisotropy_enable = .false,
            .max_anisotropy = 0.0,
            .compare_enable = .false,
            .compare_op = .always,
            .min_lod = 0.0,
            .max_lod = vk.LOD_CLAMP_NONE,
            .border_color = .float_opaque_black,
            .unnormalized_coordinates = .false,
        }, null) catch return error.InitializationFailed;
        errdefer device.proxy.destroySampler(linear_sampler, null);

        const per_frame_data = try gpa.alloc(PerFrameData, desc.frames_in_flight);
        errdefer gpa.free(per_frame_data);

        for (per_frame_data) |*frame_data| {
            frame_data.* = PerFrameData.init(gpa, device) catch return error.OutOfMemory;
        }
        errdefer {
            for (per_frame_data) |*frame_data| {
                frame_data.deinit(gpa);
            }
        }

        return .{
            .gpa = gpa,
            .backend = backend,
            .physical_device_index = physical_device_index,
            .device = device,

            .pipeline_layout = pipeline_layout,
            .linear_sampler = linear_sampler,

            .swapchains = .init(gpa),
            .shader_modules = .init(gpa),
            .graphics_pipelines = .init(gpa),
            .compute_pipelines = .init(gpa),

            .buffers = .init(gpa),
            .textures = .init(gpa),

            .per_frame_data = per_frame_data,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self.device.proxy.deviceWaitIdle() catch {};

        for (self.per_frame_data) |*frame_data| {
            frame_data.deinit(self.gpa, self.device);
        }
        self.gpa.free(self.per_frame_data);

        var shader_iter = self.shader_modules.valueIterator();
        while (shader_iter.next()) |module| {
            self.device.proxy.destroyShaderModule(module.*, null);
        }
        self.shader_modules.deinit();

        var graphics_iter = self.graphics_pipelines.valueIterator();
        while (graphics_iter.next()) |pipeline| {
            self.device.proxy.destroyPipeline(pipeline.*, null);
        }
        self.graphics_pipelines.deinit();

        var compute_iter = self.compute_pipelines.valueIterator();
        while (compute_iter.next()) |pipeline| {
            self.device.proxy.destroyPipeline(pipeline.*, null);
        }

        self.device.proxy.destroySampler(self.linear_sampler, null);
        self.device.proxy.destroyPipelineLayout(self.pipeline_layout, null);

        var swapchain_iter = self.swapchains.valueIterator();
        while (swapchain_iter.next()) |swapchain| {
            swapchain.*.deinit();
            self.gpa.destroy(swapchain.*);
        }
        self.swapchains.deinit();

        var buffer_iter = self.buffers.valueIterator();
        while (buffer_iter.next()) |info| {
            info.buffer.deinit(self.device);
        }
        self.buffers.deinit();

        var texture_iter = self.textures.valueIterator();
        while (texture_iter.next()) |info| {
            info.texture.deinit(self.device);
        }
        self.textures.deinit();

        self.device.deinit();
        self.gpa.destroy(self.device);
    }

    pub fn interface(self: *Self) saturn.DeviceInterface {
        return .{
            .ctx = self,
            .vtable = &.{
                .getInfo = getInfo,
                .createBuffer = createBuffer,
                .destroyBuffer = destroyBuffer,
                .getBufferInfo = getBufferInfo,
                .createTexture = createTexture,
                .destroyTexture = destroyTexture,
                .getTextureInfo = getTextureInfo,
                .canUploadTexture = canUploadTexture,
                .uploadTexture = uploadTexture,
                .createShaderModule = createShaderModule,
                .destroyShaderModule = destroyShaderModule,
                .createGraphicsPipeline = createGraphicsPipeline,
                .destroyGraphicsPipeline = destroyGraphicsPipeline,
                .createComputePipeline = createComputePipeline,
                .destroyComputePipeline = destroyComputePipeline,
                .claimWindow = claimWindow,
                .releaseWindow = releaseWindow,
                .submit = submit,
                .waitIdle = waitIdle,
            },
        };
    }

    fn getInfo(ctx: *anyopaque) saturn.DeviceInfo {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.backend.instance.physical_devices_info[self.physical_device_index];
    }

    fn createBuffer(ctx: *anyopaque, desc: saturn.BufferDesc) saturn.Error!saturn.BufferHandle {
        const self: *Self = @ptrCast(@alignCast(ctx));

        var buffer = Buffer.init(
            self.device,
            desc.size,
            desc.usage,
            desc.memory,
        ) catch |err| {
            return switch (err) {
                error.OutOfHostMemory, error.OutOfDeviceMemory => error.OutOfMemory,
                error.NoSuitableMemoryType => error.InvalidUsage,
                else => error.Unknown,
            };
        };
        errdefer buffer.deinit(self.device);

        const handle: saturn.BufferHandle = @enumFromInt(@intFromEnum(buffer.handle));

        self.buffers.put(handle, .{ .buffer = buffer }) catch return error.OutOfMemory;

        if (self.device.debug) {
            self.device.proxy.setDebugUtilsObjectNameEXT(&.{
                .object_type = .buffer,
                .object_handle = @intFromEnum(buffer.handle),
                .p_object_name = desc.name,
            }) catch {};
        }

        return handle;
    }

    fn destroyBuffer(ctx: *anyopaque, buffer: saturn.BufferHandle) void {
        _ = buffer; // autofix
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self; // autofix

        // if (self.buffers.fetchRemove(buffer)) |entry| {
        //     self.per_frame_data[self.frame_index].freed.buffers.append(self.gpa, entry.value) catch {
        //         if (entry.value.uniform_binding) |binding| {
        //             self.descriptor.uniform_buffer_array.clear(binding);
        //         }

        //         if (entry.value.storage_binding) |binding| {
        //             self.descriptor.storage_buffer_array.clear(binding);
        //         }

        //         entry.value.deinit(self.device);
        //     };
        // }
    }

    fn getBufferInfo(ctx: *anyopaque, handle: saturn.BufferHandle) ?saturn.BufferInfo {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return if (self.buffers.get(handle)) |info| info.buffer.getInfo() else null;
    }

    fn getBufferMappedSlice(ctx: *anyopaque, handle: saturn.BufferHandle) ?[]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.buffers.get(handle)) |info| {
            return info.buffer.allocation.getMappedByteSlice();
        }

        return null;
    }

    fn createTexture(ctx: *anyopaque, desc: saturn.TextureDesc) saturn.Error!saturn.TextureHandle {
        const self: *Self = @ptrCast(@alignCast(ctx));

        var texture = Texture.init(
            self.device,
            desc.extent,
            desc.mip_levels,
            desc.format,
            desc.usage,
            desc.memory,
        ) catch |err| {
            return switch (err) {
                error.OutOfHostMemory, error.OutOfDeviceMemory => error.OutOfMemory,
                error.NoSuitableMemoryType => error.InvalidUsage,
                else => error.Unknown,
            };
        };
        errdefer texture.deinit(self.device);

        const handle: saturn.TextureHandle = @enumFromInt(@intFromEnum(texture.handle));

        self.textures.put(handle, .{ .texture = texture }) catch return error.OutOfMemory;

        if (self.device.debug) {
            self.device.proxy.setDebugUtilsObjectNameEXT(&.{
                .object_type = .image,
                .object_handle = @intFromEnum(texture.handle),
                .p_object_name = desc.name,
            }) catch {};
        }

        return handle;
    }

    fn destroyTexture(ctx: *anyopaque, texture: saturn.TextureHandle) void {
        _ = texture; // autofix
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self; // autofix

        // if (self.textures.fetchRemove(texture)) |entry| {
        //     self.per_frame_data[self.frame_index].freed.texture.append(self.gpa, entry.value) catch {
        //         if (entry.value.sampled_binding) |binding| {
        //             self.descriptor.sampled_image_array.clear(binding);
        //         }

        //         if (entry.value.storage_binding) |binding| {
        //             self.descriptor.storage_image_array.clear(binding);
        //         }

        //         entry.value.deinit(self.device);
        //     };
        // }
    }

    fn getTextureInfo(ctx: *anyopaque, handle: saturn.TextureHandle) ?saturn.TextureInfo {
        const self: *Self = @ptrCast(@alignCast(ctx));

        return if (self.textures.get(handle)) |info| info.texture.getInfo() else null;
    }

    fn canUploadTexture(ctx: *anyopaque, handle: saturn.TextureHandle) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.device.extensions.host_image_copy) {
            if (self.textures.get(handle)) |info| {
                if (info.texture.usage.host_transfer) {
                    if (info.texture.allocation) |allocation| {
                        return allocation.mapped_ptr != null;
                    }
                }
            }
        }

        return false;
    }

    fn uploadTexture(ctx: *anyopaque, handle: saturn.TextureHandle, mip_level: u32, data: []const u8) saturn.Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        std.debug.assert(self.device.extensions.host_image_copy);

        if (self.textures.get(handle)) |info| {
            info.texture.hostImageCopy(self.device, mip_level, .shader_read_only_optimal, data) catch return error.Unknown;
        }
    }

    fn createShaderModule(ctx: *anyopaque, desc: saturn.ShaderDesc) saturn.Error!saturn.ShaderHandle {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const module = self.device.proxy.createShaderModule(&.{
            .code_size = desc.code.len * @sizeOf(u32),
            .p_code = desc.code.ptr,
        }, null) catch |err| {
            return switch (err) {
                error.OutOfHostMemory => error.OutOfMemory,
                error.OutOfDeviceMemory => error.OutOfDeviceMemory,
                else => error.InvalidUsage,
            };
        };

        const handle: saturn.ShaderHandle = @enumFromInt(@intFromEnum(module));

        self.shader_modules.put(handle, module) catch {
            self.device.proxy.destroyShaderModule(module, null);
            return error.OutOfMemory;
        };

        return handle;
    }

    fn destroyShaderModule(ctx: *anyopaque, handle: saturn.ShaderHandle) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.shader_modules.fetchRemove(handle)) |module| {
            self.device.proxy.destroyShaderModule(module.value, null);
        }
    }

    fn createGraphicsPipeline(ctx: *anyopaque, desc: *const saturn.GraphicsPipelineDesc) saturn.Error!saturn.GraphicsPipelineHandle {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const pipeline = Pipeline.createGraphicsPipeline(self, desc) catch return error.InvalidUsage;
        errdefer self.device.proxy.destroyPipeline(pipeline, null);

        const handle: saturn.GraphicsPipelineHandle = @enumFromInt(@intFromEnum(pipeline));
        try self.graphics_pipelines.put(handle, pipeline);
        return handle;
    }

    fn destroyGraphicsPipeline(ctx: *anyopaque, pipeline: saturn.GraphicsPipelineHandle) void {
        _ = pipeline; // autofix
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self; // autofix

        // if (self.graphics_pipelines.fetchRemove(pipeline)) |entry| {
        //     self.per_frame_data[self.frame_index].freed.pipelines.append(self.gpa, entry.value) catch {
        //         self.device.proxy.destroyPipeline(entry.value, null);
        //     };
        // }
    }

    fn createComputePipeline(ctx: *anyopaque, desc: saturn.ComputePipelineDesc) saturn.Error!saturn.ComputePipelineHandle {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const pipeline = Pipeline.createComputePipeline(self, &desc) catch return error.InvalidUsage;
        errdefer self.device.proxy.destroyPipeline(pipeline, null);

        const handle: saturn.ComputePipelineHandle = @enumFromInt(@intFromEnum(pipeline));
        try self.compute_pipelines.put(handle, pipeline);
        return handle;
    }

    fn destroyComputePipeline(ctx: *anyopaque, pipeline: saturn.ComputePipelineHandle) void {
        _ = pipeline; // autofix
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self; // autofix

        // if (self.compute_pipelines.fetchRemove(pipeline)) |entry| {
        //     self.per_frame_data[self.frame_index].freed.pipelines.append(self.gpa, entry.value) catch {
        //         self.device.proxy.destroyPipeline(entry.value, null);
        //     };
        // }
    }

    fn claimWindow(ctx: *anyopaque, window: saturn.WindowHandle, desc: saturn.WindowSettings) saturn.Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        // Use existing conversion functions
        const vk_present_mode = Swapchain.getVkPresentMode(desc.present_mode);

        // Get the surface for this window
        const surface = self.backend.surfaces.get(window) orelse return error.WindowLost;

        // Query the window size from the platform via callback
        const size = self.backend.get_window_size_fn(window, self.backend.get_window_size_user_data);
        const extent = vk.Extent2D{ .width = size[0], .height = size[1] };

        if (self.swapchains.get(window)) |swapchain| {
            const old_swapchain: Swapchain = swapchain.*;
            errdefer old_swapchain.deinit();

            swapchain.* = Swapchain.init(
                self.device,
                surface,
                extent,
                desc.texture_count,
                desc.texture_usage,
                desc.texture_format,
                vk_present_mode,
                null,
            ) catch |err| {
                return switch (err) {
                    error.OutOfHostMemory, error.OutOfDeviceMemory => error.OutOfMemory,
                    error.DeviceLost => error.DeviceLost,
                    error.SurfaceLostKHR => error.WindowLost,
                    else => error.Unknown,
                };
            };
        } else {
            const swapchain = try self.gpa.create(Swapchain);
            errdefer self.gpa.destroy(swapchain);

            swapchain.* = Swapchain.init(
                self.device,
                surface,
                extent,
                desc.texture_count,
                desc.texture_usage,
                desc.texture_format,
                vk_present_mode,
                null,
            ) catch |err| {
                return switch (err) {
                    error.OutOfHostMemory, error.OutOfDeviceMemory => error.OutOfMemory,
                    error.DeviceLost => error.DeviceLost,
                    error.SurfaceLostKHR => error.WindowLost,
                    else => error.Unknown,
                };
            };

            try self.swapchains.put(window, swapchain);
        }
    }

    fn releaseWindow(ctx: *anyopaque, window: saturn.WindowHandle) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.swapchains.fetchRemove(window)) |entry| {
            self.device.proxy.deviceWaitIdle() catch {};
            entry.value.deinit();
            self.gpa.destroy(entry.value);
        }
    }

    fn submit(ctx: *anyopaque, tpa: std.mem.Allocator, render_graph: *const saturn.RenderGraph) saturn.Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        var executor = render_graph_executor.RenderGraphExecutor.init(self, tpa, render_graph) catch return error.Unknown;
        defer executor.deinit();
        try executor.execute();

        return;
    }

    fn waitIdle(ctx: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = self.device.proxy.deviceWaitIdle() catch {};
    }

    pub fn getNextFrameData(self: *Self) *PerFrameData {
        defer self.frame_index = @mod(self.frame_index + 1, self.per_frame_data.len);
        return &self.per_frame_data[self.frame_index];
    }

    // *************************************************************************************************************************
    // Render Graph code starts here
    // *************************************************************************************************************************

    pub fn getBufferResource(self: *const Self, handle: saturn.BufferHandle) ?render_graph_executor.BufferResource {
        const info = self.buffers.get(handle) orelse return null;

        var resource: render_graph_executor.BufferResource = .{
            .interface = info.buffer,
            .queue = info.owner_queue,
        };

        var frame_index: usize = self.frame_index;
        for (0..(self.per_frame_data.len - 1)) |_| {
            frame_index = (frame_index + self.per_frame_data.len - 1) % self.per_frame_data.len;

            if (self.per_frame_data[frame_index].buffer_access.get(handle)) |access| {
                resource.last_access = access;
                break;
            }
        }

        return resource;
    }

    pub fn getTextureResource(self: *const Self, handle: saturn.TextureHandle) ?render_graph_executor.TextureResource {
        const info = self.textures.get(handle) orelse return null;

        var resource: render_graph_executor.TextureResource = .{
            .interface = info.texture,
            .queue = info.owner_queue,
            .layout = info.layout,
        };

        var frame_index: usize = self.frame_index;
        for (0..(self.per_frame_data.len - 1)) |_| {
            frame_index = (frame_index + self.per_frame_data.len - 1) % self.per_frame_data.len;

            if (self.per_frame_data[frame_index].texture_access.get(handle)) |access| {
                resource.last_access = access;
                break;
            }
        }

        return resource;
    }

    const BufferResource = struct {
        interface: Buffer,
        queue: ?QueueFamily,
        last_access: ?saturn.BufferAccess = null,
    };

    const TextureResource = struct {
        interface: Texture,
        queue: ?QueueFamily,
        last_access: ?saturn.TextureAccess = null,
        layout: vk.ImageLayout,
    };

    const GraphResources = struct {
        buffers: []BufferResource,
        textures: []TextureResource,

        pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.buffers);
            allocator.free(self.textures);
        }
    };

    const SwapchainTexture = struct {
        swapchain: *Swapchain,
        index: u32,
        interface: Texture,
        wait_semaphore: vk.Semaphore,
        present_semaphore: vk.Semaphore,
        resource: saturn.RGTextureHandle,
    };

    fn getTextureSize(texture_extent: saturn.RGTextureExtent, textures: []const TextureResource) vk.Extent2D {
        return switch (texture_extent) {
            .fixed => |extent| .{ .width = extent[0], .height = extent[1] },
            .relative => |rel_tex| textures[rel_tex.idx].interface.extent,
        };
    }

    pub fn fetchResources(self: *const Self, tpa: std.mem.Allocator, frame_data: *PerFrameData, render_graph: *const saturn.RenderGraph, swapchain_textures: []const SwapchainTexture) !GraphResources {

        //***************************************************
        //TODO: ACTUALLY RESUSE AND ALIAS TRANSIENT RESOURCES
        //***************************************************W

        const buffers: []BufferResource = try tpa.alloc(BufferResource, render_graph.buffers.items.len);
        errdefer tpa.free(buffers);

        const textures: []TextureResource = try tpa.alloc(TextureResource, render_graph.textures.items.len);
        errdefer tpa.free(textures);

        for (render_graph.buffers.items, buffers) |graph_buffer, *resource| {
            resource.* = switch (graph_buffer.source) {
                .persistent => |handle| self.getBufferResource(handle).?,
                .transient => |idx| result: {
                    const desc = render_graph.transient_buffers.items[idx];

                    //TODO: finish desc
                    const buffer = try Buffer.init(self.device, desc.size, .{ .storage_buffer_bit = true }, .gpu_only);
                    try frame_data.transient_buffers.append(self.gpa, buffer);
                    break :result BufferResource{
                        .interface = buffer,
                        .queue = null,
                        .last_access = null,
                    };
                },
            };
        }

        for (render_graph.textures.items, textures, 0..) |graph_texture, *resource, i| {
            resource.* = switch (graph_texture.source) {
                .persistent => |handle| self.getTextureResource(handle).?,
                .transient => |idx| result: {
                    const desc = render_graph.transient_textures.items[idx];

                    //TODO: finish desc
                    const texture = try Texture.init(
                        self.device,
                        getTextureSize(desc.extent, textures[0..i]),
                        1,
                        .r8g8b8a8_unorm,
                        .{ .storage_bit = true },
                        .gpu_only,
                    );
                    try frame_data.transient_textures.append(self.gpa, texture);
                    break :result TextureResource{
                        .interface = texture,
                        .queue = null,
                        .last_access = null,
                        .layout = .undefined,
                    };
                },
                .window => |idx| TextureResource{
                    .interface = swapchain_textures[idx].interface,
                    .queue = null,
                    .last_access = null,
                    .layout = .undefined,
                },
            };
        }

        return .{
            .buffers = buffers,
            .textures = textures,
        };
    }

    const BufferStateAccess = struct {
        access: vk.AccessFlags2,
        state: vk.PipelineStageFlags2,
    };

    pub fn getBufferStateAccess(access: saturn.BufferAccess) BufferStateAccess {
        return switch (access) {
            .none => .{
                .access = .{},
                .state = .{},
            },

            .vertex_read => .{
                .access = .{ .vertex_attribute_read_bit = true },
                .state = .{ .vertex_input_bit = true },
            },
            .index_read => .{
                .access = .{ .index_read_bit = true },
                .state = .{ .index_input_bit = true },
            },
            .indirect_read => .{
                .access = .{ .indirect_command_read_bit = true },
                .state = .{ .draw_indirect_bit = true },
            },

            .compute_uniform_read => .{
                .access = .{ .uniform_read_bit = true },
                .state = .{ .compute_shader_bit = true },
            },
            .graphics_uniform_read => .{
                .access = .{ .uniform_read_bit = true },
                .state = .{ .all_graphics_bit = true },
            },

            .compute_storage_read => .{
                .access = .{ .shader_storage_read_bit = true },
                .state = .{ .compute_shader_bit = true },
            },
            .graphics_storage_read => .{
                .access = .{ .shader_storage_read_bit = true },
                .state = .{ .all_graphics_bit = true },
            },

            .compute_storage_write => .{
                .access = .{ .shader_storage_read_bit = true, .shader_storage_write_bit = true },
                .state = .{ .compute_shader_bit = true },
            },
            .graphics_storage_write => .{
                .access = .{ .shader_storage_read_bit = true, .shader_storage_write_bit = true },
                .state = .{ .all_graphics_bit = true },
            },

            .transfer_read => .{
                .access = .{ .transfer_read_bit = true },
                .state = .{ .all_transfer_bit = true },
            },
            .transfer_write => .{
                .access = .{ .transfer_write_bit = true },
                .state = .{ .all_transfer_bit = true },
            },
        };
    }

    pub fn getBufferMemoryBarrier(
        self: *Self,
        handle: vk.Buffer,
        src_access: saturn.BufferAccess,
        dst_access: saturn.BufferAccess,
    ) vk.BufferMemoryBarrier2 {
        _ = self; // autofix

        const src = getBufferStateAccess(src_access);
        const dst = getBufferStateAccess(dst_access);

        return .{
            .buffer = handle,
            .offset = 0,
            .size = vk.WHOLE_SIZE,
            .src_access_mask = src.access,
            .src_stage_mask = src.state,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_access_mask = dst.access,
            .dst_stage_mask = dst.state,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        };
    }

    const TextureStateAccess = struct {
        access: vk.AccessFlags2,
        state: vk.PipelineStageFlags2,
        layout: vk.ImageLayout,
    };

    pub fn getTextureStateAccess(access: saturn.TextureAccess, is_color: bool, unifined_image_layout: bool) TextureStateAccess {
        var result: TextureStateAccess = switch (access) {
            .none => .{
                .access = .{},
                .state = .{},
                .layout = .undefined,
            },

            .attachment_read => if (is_color) .{
                .access = .{ .color_attachment_read_bit = true },
                .state = .{ .color_attachment_output_bit = true, .fragment_shader_bit = true },
                .layout = .attachment_optimal, //TODO: what is the best layout for this stage?
            } else .{
                .access = .{ .depth_stencil_attachment_read_bit = true },
                .state = .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true },
                .layout = .attachment_optimal,
            },
            .attachment_write => if (is_color) .{
                .access = .{ .color_attachment_write_bit = true },
                .state = .{ .color_attachment_output_bit = true },
                .layout = .attachment_optimal,
            } else .{
                .access = .{ .depth_stencil_attachment_write_bit = true },
                .state = .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true },
                .layout = .attachment_optimal,
            },

            .compute_sampled_read => .{
                .access = .{ .shader_sampled_read_bit = true },
                .state = .{ .compute_shader_bit = true },
                .layout = .shader_read_only_optimal,
            },
            .graphics_sampled_read => .{
                .access = .{ .shader_sampled_read_bit = true },
                .state = .{ .all_graphics_bit = true },
                .layout = .shader_read_only_optimal,
            },

            .compute_storage_read => .{
                .access = .{ .shader_storage_read_bit = true },
                .state = .{ .compute_shader_bit = true },
                .layout = .general,
            },
            .graphics_storage_read => .{
                .access = .{ .shader_storage_read_bit = true },
                .state = .{ .all_graphics_bit = true },
                .layout = .general,
            },

            .compute_storage_write => .{
                .access = .{ .shader_storage_read_bit = true, .shader_storage_write_bit = true },
                .state = .{ .compute_shader_bit = true },
                .layout = .general,
            },
            .graphics_storage_write => .{
                .access = .{ .shader_storage_read_bit = true, .shader_storage_write_bit = true },
                .state = .{ .all_graphics_bit = true },
                .layout = .general,
            },

            .transfer_read => .{
                .access = .{ .transfer_read_bit = true },
                .state = .{ .all_transfer_bit = true },
                .layout = .transfer_src_optimal,
            },
            .transfer_write => .{
                .access = .{ .transfer_write_bit = true },
                .state = .{ .all_transfer_bit = true },
                .layout = .transfer_dst_optimal,
            },
        };

        if (access != .none and unifined_image_layout) {
            result.layout = .general;
        }

        return result;
    }

    pub fn getTextureMemoryBarrier(
        self: *Self,
        texture: Texture,
        src_access: saturn.TextureAccess,
        dst_access: saturn.TextureAccess,
    ) ?vk.ImageMemoryBarrier2 {
        const aspect_mask = Texture.getFormatAspectMask(texture.format);
        const is_color = aspect_mask.color_bit;
        const unified_image_layouts = self.device.extensions.unified_image_layouts;

        const src = getTextureStateAccess(src_access, is_color, unified_image_layouts);
        const dst = getTextureStateAccess(dst_access, is_color, unified_image_layouts);

        return .{
            .image = texture.handle,
            .subresource_range = .{
                .aspect_mask = aspect_mask,
                .base_array_layer = 0,
                .layer_count = 1,
                .base_mip_level = 0,
                .level_count = 1,
            },
            .src_access_mask = src.access,
            .src_stage_mask = src.state,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .old_layout = src.layout,

            .dst_access_mask = dst.access,
            .dst_stage_mask = dst.state,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .new_layout = dst.layout,
        };
    }

    pub fn buildBarriers(
        self: *Self,
        tpa: std.mem.Allocator,
        command_buffer: vk.CommandBufferProxy,
        render_graph: *const saturn.RenderGraph,
        pass: saturn.RenderGraphCompiled.Pass,
        resources: *const GraphResources,
    ) !void {

        //TODO: use only single MemoryBarrier, we wont need more than one
        var memory_barriers: std.ArrayList(vk.MemoryBarrier2) = .empty;
        defer memory_barriers.deinit(tpa);

        //TODO: limit to max number, if overflow switch to single MemoryBarrier
        var buffer_barriers: std.ArrayList(vk.BufferMemoryBarrier2) = .empty;
        defer buffer_barriers.deinit(tpa);

        var texture_barriers: std.ArrayList(vk.ImageMemoryBarrier2) = .empty;
        defer texture_barriers.deinit(tpa);

        const DEBUG_FULL_PIPELINE_BARRIER: bool = false;
        if (DEBUG_FULL_PIPELINE_BARRIER) {
            try memory_barriers.append(tpa, .{
                .src_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                .src_stage_mask = .{ .all_commands_bit = true },
                .dst_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                .dst_stage_mask = .{ .all_commands_bit = true },
            });
        }

        const dst_pass = &render_graph.passes.items[pass.handle.idx];

        for (pass.first_usages.items) |first_usage| {
            switch (first_usage) {
                .buffer => |handle| {
                    const buffer = &resources.buffers[handle.idx];
                    if (buffer.last_access) |src_access| {
                        if (dst_pass.getBufferAccess(handle)) |dst_access| {
                            try buffer_barriers.append(tpa, self.getBufferMemoryBarrier(buffer.interface.handle, src_access, dst_access));
                        }
                    }
                },
                .texture => |handle| {
                    const texture = &resources.textures[handle.idx];
                    if (dst_pass.getTextureAccess(handle)) |dst_access| {
                        if (self.getTextureMemoryBarrier(texture.interface, texture.last_access orelse .none, dst_access)) |barrier| {
                            try texture_barriers.append(tpa, barrier);
                        }
                    }
                },
            }
        }

        for (pass.pass_dependencies.items) |pass_dependency| {
            const src_pass = &render_graph.passes.items[pass_dependency.pass.idx];

            for (pass_dependency.dependencies.items) |dependency| {
                switch (dependency) {
                    .buffer => |handle| {
                        const buffer = &resources.buffers[handle.idx];
                        if (src_pass.getBufferAccess(handle)) |src_access| {
                            if (dst_pass.getBufferAccess(handle)) |dst_access| {
                                try buffer_barriers.append(tpa, self.getBufferMemoryBarrier(buffer.interface.handle, src_access, dst_access));
                            }
                        }
                    },
                    .texture => |handle| {
                        const texture = &resources.textures[handle.idx];
                        if (src_pass.getTextureAccess(handle)) |src_access| {
                            if (dst_pass.getTextureAccess(handle)) |dst_access| {
                                if (self.getTextureMemoryBarrier(texture.interface, src_access, dst_access)) |barrier| {
                                    try texture_barriers.append(tpa, barrier);
                                }
                            }
                        }
                    },
                }
            }
        }

        const dependencies: vk.DependencyInfo = .{
            .memory_barrier_count = @intCast(memory_barriers.items.len),
            .p_memory_barriers = memory_barriers.items.ptr,

            .buffer_memory_barrier_count = @intCast(buffer_barriers.items.len),
            .p_buffer_memory_barriers = buffer_barriers.items.ptr,

            .image_memory_barrier_count = @intCast(texture_barriers.items.len),
            .p_image_memory_barriers = texture_barriers.items.ptr,
        };

        if (dependencies.memory_barrier_count + dependencies.buffer_memory_barrier_count + dependencies.image_memory_barrier_count > 0) {
            command_buffer.pipelineBarrier2(&dependencies);
        }
    }

    pub fn recordRenderGraph(
        self: *Self,
        tpa: std.mem.Allocator,
        frame_data: *PerFrameData,
        desc: *const saturn.RenderGraph,
        compiled: *const saturn.RenderGraphCompiled,
        resources: *const GraphResources,
        swapchain_textures: []const SwapchainTexture,
    ) !void {
        const fence = try frame_data.fence_pool.get();
        try frame_data.frame_wait_fences.append(self.gpa, fence);

        const command_buffer_handle = try frame_data.graphics_command_pool.get();
        const command_buffer = vk.CommandBufferProxy.init(command_buffer_handle, self.device.proxy.wrapper);

        try command_buffer.beginCommandBuffer(&.{});

        for (compiled.passes.items) |compiled_pass| {
            const pass = desc.passes.items[compiled_pass.handle.idx];

            if (self.device.debug) {
                const temp_name: [:0]const u8 = try tpa.dupeZ(u8, pass.name);
                command_buffer.beginDebugUtilsLabelEXT(&.{
                    .p_label_name = temp_name,
                    .color = .{ 1.0, 0.0, 1.0, 1.0 },
                });
            }
            defer if (self.device.debug) {
                command_buffer.endDebugUtilsLabelEXT();
            };

            // Generate Barriers
            try self.buildBarriers(tpa, command_buffer, desc, compiled_pass, resources);

            // Record Command Buffers

        }

        //Transitioning Swapchains to final formats
        {
            const swapchain_transitions = try tpa.alloc(vk.ImageMemoryBarrier2, swapchain_textures.len);
            defer tpa.free(swapchain_transitions);

            //TODO: generate barriers from graph info
            for (swapchain_textures, swapchain_transitions) |swapchain_texture, *memory_barrier| {

                //Get last usage
                var src_access: saturn.TextureAccess = .none;

                if (desc.textures.items[swapchain_texture.resource.idx].last_usage) |pass| {
                    if (desc.passes.items[pass.idx].getTextureAccess(swapchain_texture.resource)) |access| {
                        src_access = access;
                    }
                }

                const src_state_access = getTextureStateAccess(src_access, true, self.device.extensions.unified_image_layouts);

                memory_barrier.* = .{
                    .image = swapchain_texture.interface.handle,
                    .old_layout = src_state_access.layout,
                    .new_layout = .present_src_khr,
                    .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                    .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                    .subresource_range = .{
                        .aspect_mask = .{ .color_bit = true },
                        .base_array_layer = 0,
                        .layer_count = 1,
                        .base_mip_level = 0,
                        .level_count = 1,
                    },
                };
            }
            command_buffer.pipelineBarrier2(&.{
                .image_memory_barrier_count = @intCast(swapchain_transitions.len),
                .p_image_memory_barriers = swapchain_transitions.ptr,
            });
        }

        try command_buffer.endCommandBuffer();
        const wait_dst_stage_mask: vk.PipelineStageFlags = .{ .all_commands_bit = true };

        const wait_semaphores = try tpa.alloc(vk.Semaphore, swapchain_textures.len);
        defer tpa.free(wait_semaphores);

        const wait_dst_stage_masks = try tpa.alloc(vk.PipelineStageFlags, swapchain_textures.len);
        defer tpa.free(wait_dst_stage_masks);

        const signal_semaphores = try tpa.alloc(vk.Semaphore, swapchain_textures.len);
        defer tpa.free(signal_semaphores);

        for (swapchain_textures, 0..) |swapchain_info, i| {
            wait_dst_stage_masks[i] = wait_dst_stage_mask;
            wait_semaphores[i] = swapchain_info.wait_semaphore;
            signal_semaphores[i] = swapchain_info.present_semaphore;
        }

        const submit_infos: [1]vk.SubmitInfo = .{vk.SubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&command_buffer_handle),
            .wait_semaphore_count = @intCast(wait_semaphores.len),
            .p_wait_semaphores = wait_semaphores.ptr,
            .p_wait_dst_stage_mask = wait_dst_stage_masks.ptr,
            .signal_semaphore_count = @intCast(signal_semaphores.len),
            .p_signal_semaphores = signal_semaphores.ptr,
        }};

        try self.device.proxy.queueSubmit(self.device.graphics_queue.handle, @intCast(submit_infos.len), &submit_infos, fence);
    }
};

pub const CommandEncoderData = struct {
    const Self = @This();

    tpa: std.mem.Allocator,
    command_buffer: vk.CommandBufferProxy,
    graph_resources: render_graph_executor.GraphResources,
    device: *const Device,

    pub fn getBuffer(self: *const Self, buffer: saturn.BufferArg) ?Buffer {
        return switch (buffer) {
            .tracked => |handle| self.graph_resources.buffers[handle.idx].interface,
            .untracked => |handle| if (self.device.buffers.get(handle)) |info| info.buffer else null,
        };
    }
    pub fn getTexture(self: *const Self, texture: saturn.TextureArg) ?Texture {
        return switch (texture) {
            .tracked => |handle| self.graph_resources.textures[handle.idx].interface,
            .untracked => |handle| if (self.device.textures.get(handle)) |info| info.texture else null,
        };
    }

    fn getBufferInfo(ctx: *anyopaque, handle: saturn.BufferArg) ?saturn.BufferInfo {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        if (cmd_data.getBuffer(handle)) |buffer| {
            return buffer.getInfo();
        }
        return null;
    }

    fn getTextureInfo(ctx: *anyopaque, handle: saturn.TextureArg) ?saturn.TextureInfo {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        if (cmd_data.getTexture(handle)) |texture| {
            return texture.getInfo();
        }
        return null;
    }
};

pub const TransferCommandEncoder = struct {
    pub const Vtable: saturn.TransferCommandEncoder.VTable = .{
        .getBufferInfo = CommandEncoderData.getBufferInfo,
        .getTextureInfo = CommandEncoderData.getTextureInfo,
        .updateBuffer = updateBuffer,
        .copyBuffer = copyBuffer,
        .copyTexture = copyTexture,
        .copyBufferToTexture = copyBufferToTexture,
        .copyTextureToBuffer = copyTextureToBuffer,
    };

    fn updateBuffer(ctx: *anyopaque, dst: saturn.BufferArg, offset: u64, data: []const u8) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const buffer = cmd_data.getBuffer(dst) orelse @panic("Invalid buffer");
        cmd_data.command_buffer.updateBuffer(buffer.handle, @intCast(offset), @intCast(data.len), data.ptr);
    }

    fn copyBuffer(ctx: *anyopaque, src: saturn.BufferArg, dst: saturn.BufferArg, regions: []const saturn.BufferCopyRegion) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));

        const src_buffer = cmd_data.getBuffer(src) orelse @panic("Invalid src buffer");
        const dst_buffer = cmd_data.getBuffer(dst) orelse @panic("Invalid dst buffer");

        const vk_regions: []vk.BufferCopy2 = cmd_data.tpa.alloc(vk.BufferCopy2, regions.len) catch @panic("Failed to alloc");
        defer cmd_data.tpa.free(vk_regions);

        for (vk_regions, regions) |*vk_region, region| {
            vk_region.* = .{ .src_offset = region.src_offset, .dst_offset = region.dst_offset, .size = region.size };
        }

        cmd_data.command_buffer.copyBuffer2(&.{
            .src_buffer = src_buffer.handle,
            .dst_buffer = dst_buffer.handle,
            .region_count = @intCast(vk_regions.len),
            .p_regions = vk_regions.ptr,
        });
    }

    fn copyTexture(ctx: *anyopaque, src: saturn.TextureArg, dst: saturn.TextureArg, regions: []const saturn.TextureCopyRegion) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));

        const src_texture = cmd_data.getTexture(src) orelse @panic("Invalid src texture");
        const dst_texture = cmd_data.getTexture(dst) orelse @panic("Invalid dst texture");

        const vk_regions = cmd_data.tpa.alloc(vk.ImageCopy2, regions.len) catch @panic("Failed to alloc");
        defer cmd_data.tpa.free(vk_regions);

        for (vk_regions, regions) |*vk_region, region| {
            vk_region.* = .{
                .src_subresource = .{
                    .aspect_mask = Texture.getFormatAspectMask(src_texture.format),
                    .mip_level = region.src_mip_level,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .src_offset = .{ .x = @intCast(region.src_offset[0]), .y = @intCast(region.src_offset[1]), .z = @intCast(region.src_offset[2]) },
                .dst_subresource = .{
                    .aspect_mask = Texture.getFormatAspectMask(dst_texture.format),
                    .mip_level = region.dst_mip_level,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .dst_offset = .{ .x = @intCast(region.dst_offset[0]), .y = @intCast(region.dst_offset[1]), .z = @intCast(region.dst_offset[2]) },
                .extent = .{ .width = region.extent.width, .height = region.extent.height, .depth = region.extent.depth },
            };
        }

        const src_layout: vk.ImageLayout = if (cmd_data.device.device.extensions.unified_image_layouts) .general else .transfer_src_optimal;
        const dst_layout: vk.ImageLayout = if (cmd_data.device.device.extensions.unified_image_layouts) .general else .transfer_dst_optimal;

        cmd_data.command_buffer.copyImage2(&.{
            .src_image = src_texture.handle,
            .src_image_layout = src_layout,
            .dst_image = dst_texture.handle,
            .dst_image_layout = dst_layout,
            .region_count = @intCast(vk_regions.len),
            .p_regions = vk_regions.ptr,
        });
    }

    fn copyBufferToTexture(ctx: *anyopaque, src: saturn.BufferArg, dst: saturn.TextureArg, regions: []const saturn.BufferTextureCopyRegion) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const src_buffer = cmd_data.getBuffer(src) orelse @panic("Invalid src buffer");
        const dst_texture = cmd_data.getTexture(dst) orelse @panic("Invalid dst texture");
        const vk_regions = cmd_data.tpa.alloc(vk.BufferImageCopy2, regions.len) catch @panic("Failed to alloc");
        defer cmd_data.tpa.free(vk_regions);
        for (vk_regions, regions) |*vk_region, region| {
            vk_region.* = .{
                .buffer_offset = region.buffer_offset,
                .buffer_row_length = region.buffer_row_length,
                .buffer_image_height = region.buffer_image_height,
                .image_subresource = .{
                    .aspect_mask = Texture.getFormatAspectMask(dst_texture.format),
                    .mip_level = region.texture_mip_level,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .image_offset = .{ .x = @intCast(region.texture_offset[0]), .y = @intCast(region.texture_offset[1]), .z = @intCast(region.texture_offset[2]) },
                .image_extent = .{ .width = region.extent.width, .height = region.extent.height, .depth = region.extent.depth },
            };
        }
        const dst_layout: vk.ImageLayout = if (cmd_data.device.device.extensions.unified_image_layouts) .general else .transfer_dst_optimal;
        cmd_data.command_buffer.copyBufferToImage2(&.{
            .src_buffer = src_buffer.handle,
            .dst_image = dst_texture.handle,
            .dst_image_layout = dst_layout,
            .region_count = @intCast(vk_regions.len),
            .p_regions = vk_regions.ptr,
        });
    }

    fn copyTextureToBuffer(ctx: *anyopaque, src: saturn.TextureArg, dst: saturn.BufferArg, regions: []const saturn.BufferTextureCopyRegion) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const src_texture = cmd_data.getTexture(src) orelse @panic("Invalid src texture");
        const dst_buffer = cmd_data.getBuffer(dst) orelse @panic("Invalid dst buffer");
        const vk_regions = cmd_data.tpa.alloc(vk.BufferImageCopy2, regions.len) catch @panic("Failed to alloc");
        defer cmd_data.tpa.free(vk_regions);
        for (vk_regions, regions) |*vk_region, region| {
            vk_region.* = .{
                .buffer_offset = region.buffer_offset,
                .buffer_row_length = region.buffer_row_length,
                .buffer_image_height = region.buffer_image_height,
                .image_subresource = .{
                    .aspect_mask = Texture.getFormatAspectMask(src_texture.format),
                    .mip_level = region.texture_mip_level,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
                .image_offset = .{ .x = @intCast(region.texture_offset[0]), .y = @intCast(region.texture_offset[1]), .z = @intCast(region.texture_offset[2]) },
                .image_extent = .{ .width = region.extent.width, .height = region.extent.height, .depth = region.extent.depth },
            };
        }
        const src_layout: vk.ImageLayout = if (cmd_data.device.device.extensions.unified_image_layouts) .general else .transfer_src_optimal;
        cmd_data.command_buffer.copyImageToBuffer2(&.{
            .src_image = src_texture.handle,
            .src_image_layout = src_layout,
            .dst_buffer = dst_buffer.handle,
            .region_count = @intCast(vk_regions.len),
            .p_regions = vk_regions.ptr,
        });
    }
};

pub const ComputeCommandEncoder = struct {
    pub const Vtable: saturn.ComputeCommandEncoder.VTable = .{
        .getBufferInfo = CommandEncoderData.getBufferInfo,
        .getTextureInfo = CommandEncoderData.getTextureInfo,
        .pushConstantsRaw = pushConstantsRaw,
        .setPipeline = setPipeline,
        .dispatch = dispatch,
        .dispatchIndirect = dispatchIndirect,
    };

    fn pushConstantsRaw(ctx: *anyopaque, data: []const u8) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        cmd_data.command_buffer.pushConstants(
            cmd_data.device.pipeline_layout,
            .{ .compute_bit = true },
            0,
            @intCast(data.len),
            data.ptr,
        );
    }

    fn setPipeline(ctx: *anyopaque, pipeline: saturn.ComputePipelineHandle) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const compute_pipeline = cmd_data.device.compute_pipelines.get(pipeline) orelse @panic("Invalid ComputePipelineHandle");
        cmd_data.command_buffer.bindPipeline(.compute, compute_pipeline.handle);
    }

    fn dispatch(ctx: *anyopaque, x: u32, y: u32, z: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        cmd_data.command_buffer.dispatch(x, y, z);
    }

    fn dispatchIndirect(ctx: *anyopaque, buffer: saturn.BufferArg, offset: u64) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const indirect_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid indirect buffer");
        cmd_data.command_buffer.dispatchIndirect(indirect_buffer.handle, offset);
    }
};

pub const GraphicsCommandEncoder = struct {
    pub const Vtable: saturn.GraphicsCommandEncoder.VTable = .{
        .getBufferInfo = CommandEncoderData.getBufferInfo,
        .getTextureInfo = CommandEncoderData.getTextureInfo,
        .pushConstantsRaw = pushConstantsRaw,
        .setVertexBuffer = setVertexBuffer,
        .setIndexBuffer = setIndexBuffer,
        .setViewport = setViewport,
        .setScissor = setScissor,
        .setPipeline = setPipeline,

        .draw = draw,
        .drawIndirect = drawIndirect,
        .drawIndirectCount = drawIndirectCount,

        .drawIndexed = drawIndexed,
        .drawIndexedIndirect = drawIndexedIndirect,
        .drawIndexedIndirectCount = drawIndexedIndirectCount,

        .drawMeshTasks = drawMeshTasks,
        .drawMeshTasksIndirect = drawMeshTasksIndirect,
        .drawMeshTasksIndirectCount = drawMeshTasksIndirectCount,
    };

    fn pushConstantsRaw(ctx: *anyopaque, data: []const u8) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));

        const mesh_shading = cmd_data.device.device.extensions.mesh_shading;

        cmd_data.command_buffer.pushConstants(
            cmd_data.device.pipeline_layout,
            .{ .vertex_bit = true, .fragment_bit = true, .mesh_bit_ext = mesh_shading, .task_bit_ext = mesh_shading },
            0,
            @intCast(data.len),
            data.ptr,
        );
    }

    fn setVertexBuffer(ctx: *anyopaque, binding: u32, buffer: saturn.BufferArg, offset: u64) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const vk_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid vertex buffer");
        cmd_data.command_buffer.bindVertexBuffers(binding, 1, &vk_buffer.handle, &offset);
    }

    fn setIndexBuffer(ctx: *anyopaque, buffer: saturn.BufferArg, index_type: saturn.IndexType, offset: u64) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const vk_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid index buffer");
        const vk_index_type: vk.IndexType = switch (index_type) {
            .u16 => .uint16,
            .u32 => .uint32,
        };
        cmd_data.command_buffer.bindIndexBuffer(vk_buffer.handle, offset, vk_index_type);
    }

    fn setViewport(ctx: *anyopaque, viewport: saturn.Viewport) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        cmd_data.command_buffer.setViewport(0, 1, &.{.{
            .x = viewport.x,
            .y = viewport.y,
            .width = viewport.width,
            .height = viewport.height,
            .min_depth = viewport.min_depth,
            .max_depth = viewport.max_depth,
        }});
    }

    fn setScissor(ctx: *anyopaque, rect: saturn.Rect2D) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        cmd_data.command_buffer.setScissor(0, 1, &.{.{
            .offset = .{ .x = rect.x, .y = rect.y },
            .extent = .{ .width = rect.width, .height = rect.height },
        }});
    }

    fn setPipeline(ctx: *anyopaque, pipeline: saturn.GraphicsPipelineHandle) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const graphics_pipeline = cmd_data.device.graphics_pipelines.get(pipeline) orelse @panic("Invalid GraphicsPipelineHandle");
        cmd_data.command_buffer.bindPipeline(.graphics, graphics_pipeline.handle);
    }

    fn draw(ctx: *anyopaque, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        cmd_data.command_buffer.draw(vertex_count, instance_count, first_vertex, first_instance);
    }

    fn drawIndirect(ctx: *anyopaque, buffer: saturn.BufferArg, offset: u64, draw_count: u32, stride: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const indirect_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid indirect buffer");
        cmd_data.command_buffer.drawIndirect(indirect_buffer.handle, offset, draw_count, stride);
    }

    fn drawIndirectCount(ctx: *anyopaque, buffer: saturn.BufferArg, offset: u64, count_buffer: saturn.BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const indirect_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid indirect buffer");
        const vk_count_buffer = cmd_data.getBuffer(count_buffer) orelse @panic("Invalid indirect count buffer");
        cmd_data.command_buffer.drawIndirectCount(indirect_buffer.handle, offset, vk_count_buffer.handle, count_offset, max_draw_count, stride);
    }

    fn drawIndexed(ctx: *anyopaque, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        cmd_data.command_buffer.drawIndexed(index_count, instance_count, first_index, vertex_offset, first_instance);
    }

    fn drawIndexedIndirect(ctx: *anyopaque, buffer: saturn.BufferArg, offset: u64, draw_count: u32, stride: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const indirect_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid indirect buffer");
        cmd_data.command_buffer.drawIndexedIndirect(indirect_buffer.handle, offset, draw_count, stride);
    }

    fn drawIndexedIndirectCount(ctx: *anyopaque, buffer: saturn.BufferArg, offset: u64, count_buffer: saturn.BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        const indirect_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid indirect buffer");
        const vk_count_buffer = cmd_data.getBuffer(count_buffer) orelse @panic("Invalid indirect count buffer");
        cmd_data.command_buffer.drawIndexedIndirectCount(indirect_buffer.handle, offset, vk_count_buffer.handle, count_offset, max_draw_count, stride);
    }

    fn drawMeshTasks(ctx: *anyopaque, x: u32, y: u32, z: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        if (!cmd_data.device.device.extensions.mesh_shading) @panic("MeshShading not enabled/supported");
        cmd_data.command_buffer.drawMeshTasksEXT(x, y, z);
    }

    fn drawMeshTasksIndirect(ctx: *anyopaque, buffer: saturn.BufferArg, offset: u64, draw_count: u32, stride: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        if (!cmd_data.device.device.extensions.mesh_shading) @panic("MeshShading not enabled/supported");
        const indirect_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid indirect buffer");
        cmd_data.command_buffer.drawMeshTasksIndirectEXT(indirect_buffer.handle, offset, draw_count, stride);
    }

    fn drawMeshTasksIndirectCount(ctx: *anyopaque, buffer: saturn.BufferArg, offset: u64, count_buffer: saturn.BufferArg, count_offset: u64, max_draw_count: u32, stride: u32) void {
        const cmd_data: *const CommandEncoderData = @ptrCast(@alignCast(ctx));
        if (!cmd_data.device.device.extensions.mesh_shading) @panic("MeshShading not enabled/supported");
        const indirect_buffer = cmd_data.getBuffer(buffer) orelse @panic("Invalid indirect buffer");
        const vk_count_buffer = cmd_data.getBuffer(count_buffer) orelse @panic("Invalid indirect count buffer");
        cmd_data.command_buffer.drawMeshTasksIndirectCountEXT(
            indirect_buffer.handle,
            offset,
            vk_count_buffer.handle,
            count_offset,
            max_draw_count,
            stride,
        );
    }
};
