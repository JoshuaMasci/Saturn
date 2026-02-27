const std = @import("std");

const vk = @import("vulkan");

const HandlePool = @import("../../containers.zig").SlotMap;
const sdl3 = @import("../../platform/sdl3.zig");
const Vulkan = sdl3.Vulkan;
const Window = sdl3.Window;
const BindlessDescriptor = @import("bindless_descriptor.zig");
const Buffer = @import("buffer.zig");
const Device = @import("device.zig");
const Image = @import("image.zig");
const Instance = @import("instance.zig");
const object_pools = @import("object_pools.zig");
const rg = @import("render_graph.zig");
pub const RenderGraph = rg.RenderGraph;
pub const RenderPass = rg.RenderPass;
const Sampler = @import("sampler.zig");
const Swapchain = @import("swapchain.zig");
const TransferQueue = @import("transfer_queue.zig");

const RenderGraph2 = @import("../render_graph.zig");

const Desc = struct {
    frames_in_flight_count: u8,
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
    texture: Image,
    owner_queue: ?QueueFamily = null,
    layout: vk.ImageLayout = .undefined,
};

const WindowInfo = struct {
    surface: vk.SurfaceKHR,
    swapchain: *Swapchain,
};

const BufferPool = HandlePool(BufferInfo);
const ImagePool = HandlePool(TextureInfo);
const SamplerPool = HandlePool(Sampler);

pub const BufferHandle = BufferPool.Handle;
pub const ImageHandle = ImagePool.Handle;
pub const SamplerHandle = SamplerPool.Handle;

const PerFrameData = struct {
    frame_wait_fences: std.ArrayList(vk.Fence) = .empty,
    graphics_command_pool: object_pools.CommandBufferPool,
    semaphore_pool: object_pools.SemaphorePool,
    fence_pool: object_pools.FencePool,

    transient_buffers: std.ArrayList(BufferHandle) = .empty,
    transient_images: std.ArrayList(ImageHandle) = .empty,

    upload_src_buffer: ?Buffer = null,

    transfer_queue: TransferQueue,

    buffer_access: std.AutoArrayHashMap(BufferHandle, RenderGraph2.BufferAccess),
    texture_access: std.AutoArrayHashMap(ImageHandle, RenderGraph2.TextureAccess),

    transient_buffers2: std.ArrayList(Buffer) = .empty,
    transient_textures2: std.ArrayList(Image) = .empty,

    pub fn waitForPrevious(self: *@This(), device: vk.DeviceProxy, timeout_ns: u64) bool {
        if (self.frame_wait_fences.items.len > 0) {
            defer self.frame_wait_fences.clearRetainingCapacity();
            _ = device.waitForFences(@intCast(self.frame_wait_fences.items.len), self.frame_wait_fences.items.ptr, .true, timeout_ns) catch return false;
        }
        return true;
    }

    pub fn reset(self: *@This()) void {
        self.frame_wait_fences.clearRetainingCapacity();
        self.graphics_command_pool.reset();
        self.semaphore_pool.reset();
        self.fence_pool.reset();
        self.transient_buffers.clearRetainingCapacity();
        self.transient_images.clearRetainingCapacity();

        self.buffer_access.clearRetainingCapacity();
        self.texture_access.clearRetainingCapacity();

        for (self.transient_buffers2.items) |buffer| {
            buffer.deinit();
        }
        self.transient_buffers2.clearRetainingCapacity();

        for (self.transient_textures2.items) |texture| {
            texture.deinit();
        }
        self.transient_textures2.clearRetainingCapacity();
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

const MaxFrameInFlightCount = 4;

const Self = @This();

allocator: std.mem.Allocator,
instance: Instance,

device: *Device,
bindless_descriptor: *BindlessDescriptor,
bindless_layout: vk.PipelineLayout,

swapchains: std.AutoArrayHashMap(Window, WindowInfo),

buffers: BufferPool,
images: ImagePool,
linear_sampler: Sampler,

frame_index: usize = 0,
frame_data: []PerFrameData,

pub fn init(allocator: std.mem.Allocator, desc: Desc) !Self {
    if (desc.frames_in_flight_count == 0 or desc.frames_in_flight_count > MaxFrameInFlightCount) {
        return error.InvalidFramesInFlightCount;
    }

    const instance = try Instance.init(
        allocator,
        Vulkan.getProcInstanceFunction().?,
        Vulkan.getInstanceExtensions(),
        .{ .name = "Saturn Engine", .version = Instance.makeVersion(0, 0, 0, 1) },
        @import("builtin").mode == .Debug,
    );
    errdefer instance.deinit();

    var device_index_opt: ?usize = null;
    std.log.info("Available Physical Devices:", .{});
    for (instance.physical_devices, 0..) |physical_device, i| {
        std.log.info("{}: {f}", .{ i, physical_device.info });

        if (device_index_opt == null and physical_device.info.type == .discrete_gpu) {
            device_index_opt = i;
        }
    }

    const device_index = device_index_opt orelse 0;
    const p_device = instance.physical_devices[device_index];

    std.log.info("Picking Device {}: {s}", .{ device_index, p_device.info.name });

    var device = try allocator.create(Device);
    errdefer allocator.destroy(device);

    device.* = try .init(
        allocator,
        instance.instance,
        p_device,
        .{
            .mesh_shading = p_device.info.extensions.mesh_shading,
            .raytracing = p_device.info.extensions.raytracing,
            .host_image_copy = p_device.info.extensions.host_image_copy and p_device.info.memory.direct_buffer_upload,
            .unified_image_layouts = p_device.info.extensions.unified_image_layouts and false,
        },
        instance.debug_messager != null,
    );
    errdefer device.deinit();

    var bindless_descriptor = try allocator.create(BindlessDescriptor);
    errdefer allocator.destroy(bindless_descriptor);

    const DESCRIPTOR_COUNT = 4096;
    bindless_descriptor.* = try BindlessDescriptor.init(allocator, device, .{
        .uniform_buffers = DESCRIPTOR_COUNT,
        .storage_buffers = DESCRIPTOR_COUNT,
        .sampled_images = DESCRIPTOR_COUNT,
        .storage_images = DESCRIPTOR_COUNT,
    });
    errdefer bindless_descriptor.deinit();

    const bindless_layout = try device.proxy.createPipelineLayout(&.{
        .set_layout_count = 1,
        .p_set_layouts = (&bindless_descriptor.layout)[0..1],
        .push_constant_range_count = 1,
        .p_push_constant_ranges = (&vk.PushConstantRange{
            .stage_flags = device.all_stage_flags,
            .offset = 0,
            .size = 256,
        })[0..1],
    }, null);
    errdefer device.proxy.destroyPipelineLayout(bindless_layout, null);

    const frame_data = try allocator.alloc(PerFrameData, @intCast(desc.frames_in_flight_count));
    errdefer allocator.free(frame_data);

    for (frame_data) |*data| {
        data.* = .{
            .graphics_command_pool = try .init(allocator, device, device.graphics_queue),
            .semaphore_pool = .init(allocator, device, .binary, 0),
            .fence_pool = .init(allocator, device, .{}),
            .transfer_queue = try .init(allocator, device, 256 * 1024 * 1024), //256Mb of staging space
            .buffer_access = .init(allocator),
            .texture_access = .init(allocator),
        };
    }

    return .{
        .allocator = allocator,
        .instance = instance,
        .device = device,
        .bindless_descriptor = bindless_descriptor,
        .bindless_layout = bindless_layout,
        .swapchains = .init(allocator),
        .buffers = .init(allocator),
        .images = .init(allocator),
        .linear_sampler = try .init(device, .linear, .repeat),

        .frame_data = frame_data,
    };
}

pub fn deinit(self: *Self) void {
    _ = self.device.proxy.deviceWaitIdle() catch {};

    for (self.frame_data) |*data| {
        data.reset();

        data.frame_wait_fences.deinit(self.allocator);
        data.graphics_command_pool.deinit();
        data.semaphore_pool.deinit();
        data.fence_pool.deinit();
        data.transient_buffers.deinit(self.allocator);
        data.transient_images.deinit(self.allocator);
        data.transfer_queue.deinit();

        data.buffer_access.deinit();

        data.transient_buffers2.deinit(self.allocator);
        data.transient_textures2.deinit(self.allocator);

        if (data.upload_src_buffer) |buffer| {
            buffer.deinit();
        }
    }

    self.allocator.free(self.frame_data);

    for (self.swapchains.values()) |surface_swapchain| {
        surface_swapchain.swapchain.deinit();
        Vulkan.destroySurface(self.instance.instance.handle, surface_swapchain.surface, null);
    }
    self.swapchains.deinit();

    self.linear_sampler.deinit();

    {
        var iter = self.buffers.iterator();
        while (iter.nextValue()) |value| {
            value.buffer.deinit();
        }
        self.buffers.deinit();
    }

    {
        var iter = self.images.iterator();
        while (iter.nextValue()) |value| {
            value.texture.deinit();
        }
        self.images.deinit();
    }

    self.device.proxy.destroyPipelineLayout(self.bindless_layout, null);
    self.bindless_descriptor.deinit();
    self.allocator.destroy(self.bindless_descriptor);
    self.device.deinit();
    self.allocator.destroy(self.device);
    self.instance.deinit();
}

pub fn waitIdle(self: *const Self) void {
    self.device.proxy.deviceWaitIdle() catch |err| {
        std.log.err("Failed to wait for device idle: {}", .{err});
    };
}

pub fn claimWindow(self: *Self, window: Window, settings: Swapchain.Settings) !void {
    if (!self.swapchains.contains(window)) {
        const surface = Vulkan.createSurface(self.instance.instance.handle, window, null).?;
        errdefer Vulkan.destroySurface(self.instance.instance.handle, surface, null);

        const window_size = window.getSize();
        const swapchain = try self.allocator.create(Swapchain);
        errdefer self.allocator.destroy(swapchain);

        swapchain.* = try Swapchain.init(
            self.device,
            surface,
            .{ .width = window_size[0], .height = window_size[1] },
            settings,
            null,
        );
        errdefer swapchain.deinit();

        try self.swapchains.put(window, .{ .surface = surface, .swapchain = swapchain });
    }
}

pub fn releaseWindow(self: *Self, window: Window) void {
    _ = self.device.proxy.deviceWaitIdle() catch {};

    if (self.swapchains.fetchSwapRemove(window)) |entry| {
        entry.value.swapchain.deinit();
        Vulkan.destroySurface(self.instance.instance.handle, entry.value.surface, null);
        self.allocator.destroy(entry.value.swapchain);
    }
}

pub fn createBuffer(self: *Self, name: []const u8, size: usize, usage: vk.BufferUsageFlags) !BufferPool.Handle {
    var buffer: Buffer = try .init(self.device, size, usage, if (self.device.physical_device.info.memory.direct_buffer_upload) .gpu_mappable else .gpu_only);
    errdefer buffer.deinit();

    self.device.setDebugName(.buffer, buffer.handle, name);

    if (usage.contains(.{ .uniform_buffer_bit = true })) {
        buffer.uniform_binding = self.bindless_descriptor.uniform_buffer_array.bind(buffer);
    }

    if (usage.contains(.{ .storage_buffer_bit = true })) {
        buffer.storage_binding = self.bindless_descriptor.storage_buffer_array.bind(buffer);
    }

    return self.buffers.insert(.{ .buffer = buffer });
}

pub fn createBufferWithData(self: *Self, name: []const u8, usage: vk.BufferUsageFlags, data: []const u8) !BufferPool.Handle {
    var temp_usage = usage;
    if (!self.device.physical_device.info.memory.direct_buffer_upload) {
        temp_usage.transfer_src_bit = true;
        temp_usage.transfer_dst_bit = true;
    }

    var buffer: Buffer = try .init(self.device, data.len, temp_usage, if (self.device.physical_device.info.memory.direct_buffer_upload) .gpu_mappable else .gpu_only);
    errdefer buffer.deinit();

    self.device.setDebugName(.buffer, buffer.handle, name);

    if (usage.contains(.{ .uniform_buffer_bit = true })) {
        buffer.uniform_binding = self.bindless_descriptor.uniform_buffer_array.bind(buffer);
    }

    if (usage.contains(.{ .storage_buffer_bit = true })) {
        buffer.storage_binding = self.bindless_descriptor.storage_buffer_array.bind(buffer);
    }

    const buffer_handle = try self.buffers.insert(.{ .buffer = buffer });

    if (buffer.allocation.getMappedByteSlice()) |buffer_slice| {
        std.debug.assert(buffer_slice.len >= data.len);
        @memcpy(buffer_slice[0..data.len], data);
    } else {
        try self.frame_data[self.frame_index].transfer_queue.writeBuffer(buffer_handle, 0, data);
    }

    return buffer_handle;
}

pub fn destroyBuffer(self: *Self, handle: BufferPool.Handle) void {
    if (self.buffers.remove(handle)) |info| {
        if (info.buffer.uniform_binding) |binding| {
            self.bindless_descriptor.uniform_buffer_array.clear(binding);
        }

        if (info.buffer.storage_binding) |binding| {
            self.bindless_descriptor.storage_buffer_array.clear(binding);
        }

        info.buffer.deinit(); //TODO: delete after buffer has left pipeline
    } else {
        std.log.err("Invalid Buffer Handle: {}", .{handle});
    }
}

pub fn getBufferMappedSlice(self: *Self, handle: BufferPool.Handle) ?[]u8 {
    return self.buffers.getPtr(handle).?.buffer.allocation.getMappedByteSlice();
}

pub fn writeBuffer(self: *Self, handle: BufferPool.Handle, offset: usize, data: []const u8) TransferQueue.WriteBufferError!void {
    try self.getTransferQueue().writeBuffer(handle, offset, data);
}

pub fn createImage(self: *Self, size: [2]u32, format: vk.Format, usage: vk.ImageUsageFlags) !ImagePool.Handle {
    var image: Image = try .init2D(self.device, .{ .width = size[0], .height = size[1] }, format, usage, .gpu_only);
    errdefer image.deinit();

    if (usage.contains(.{ .sampled_bit = true })) {
        image.sampled_binding = self.bindless_descriptor.sampled_image_array.bind(image, self.linear_sampler);
    }

    if (usage.contains(.{ .storage_bit = true })) {
        image.storage_binding = self.bindless_descriptor.storage_image_array.bind(image, null);
    }

    return self.images.insert(.{ .texture = image });
}
pub fn createImageWithData(self: *Self, name: []const u8, size: [2]u32, format: vk.Format, usage: vk.ImageUsageFlags, data: []const u8) !ImagePool.Handle {
    var usage_flags = usage;
    if (self.device.extensions.host_image_copy) {
        usage_flags.host_transfer_bit = true;
    } else {
        usage_flags.transfer_dst_bit = true;
    }

    var image: Image = try .init2D(self.device, .{ .width = size[0], .height = size[1] }, format, usage_flags, .gpu_only);
    errdefer image.deinit();

    self.device.setDebugName(.image, image.handle, name);

    if (usage.contains(.{ .sampled_bit = true })) {
        image.sampled_binding = self.bindless_descriptor.sampled_image_array.bind(image, self.linear_sampler);
    }

    if (usage.contains(.{ .storage_bit = true })) {
        image.storage_binding = self.bindless_descriptor.storage_image_array.bind(image, null);
    }

    const image_handle = try self.images.insert(.{ .texture = image });

    if (self.device.extensions.host_image_copy) {
        try image.hostImageCopy(self.device, .shader_read_only_optimal, data);
    } else {
        try self.getTransferQueue().writeTexture(image_handle, .shader_read_only_optimal, data);
    }

    return image_handle;
}
pub fn destroyImage(self: *Self, handle: ImagePool.Handle) void {
    if (self.images.remove(handle)) |info| {
        if (info.texture.sampled_binding) |binding| {
            self.bindless_descriptor.sampled_image_array.clear(binding);
        }

        if (info.texture.storage_binding) |binding| {
            self.bindless_descriptor.storage_image_array.clear(binding);
        }

        info.texture.deinit(); //TODO: delete after image has left pipeline
    } else {
        std.log.err("Invalid Image Handle: {}", .{handle});
    }
}

pub fn getTransferQueue(self: *Self) *TransferQueue {
    return &self.frame_data[self.frame_index].transfer_queue;
}

pub fn getNextFrameData(self: *Self) *PerFrameData {
    defer self.frame_index = @mod(self.frame_index + 1, self.frame_data.len);
    return &self.frame_data[self.frame_index];
}

// *************************************************************************************************************************
// New Graph code starts here
// *************************************************************************************************************************
// TODO: move this to somewhere better

pub fn getBufferResource(self: *const Self, handle: BufferHandle) ?BufferResource {
    const info = self.buffers.get(handle) orelse return null;

    var resource: BufferResource = .{
        .interface = info.buffer.interface(),
        .queue = info.owner_queue,
    };

    var frame_index: usize = self.frame_index;
    for (0..(self.frame_data.len - 1)) |_| {
        frame_index = (frame_index + self.frame_data.len - 1) % self.frame_data.len;

        if (self.frame_data[frame_index].buffer_access.get(handle)) |access| {
            resource.last_access = access;
            break;
        }
    }

    return resource;
}

pub fn getTextureResource(self: *const Self, handle: ImageHandle) ?TextureResource {
    const info = self.images.get(handle) orelse return null;

    var resource: TextureResource = .{
        .interface = info.texture.interface(),
        .queue = info.owner_queue,
        .layout = info.layout,
    };

    var frame_index: usize = self.frame_index;
    for (0..(self.frame_data.len - 1)) |_| {
        frame_index = (frame_index + self.frame_data.len - 1) % self.frame_data.len;

        if (self.frame_data[frame_index].texture_access.get(handle)) |access| {
            resource.last_access = access;
            break;
        }
    }

    return resource;
}

const BufferResource = struct {
    interface: Buffer.Interface,
    queue: ?QueueFamily,
    last_access: ?RenderGraph2.BufferAccess = null,
};

const TextureResource = struct {
    interface: Image.Interface,
    queue: ?QueueFamily,
    last_access: ?RenderGraph2.TextureAccess = null,
    layout: vk.ImageLayout,
};

const GraphResources = struct {
    buffers: []BufferResource,
    textures: []TextureResource,
};

fn getTextureSize(texture_extent: RenderGraph2.TextureExtent, textures: []const TextureResource) vk.Extent2D {
    return switch (texture_extent) {
        .fixed => |extent| .{ .width = extent[0], .height = extent[1] },
        .relative => |rel_tex| textures[rel_tex.idx].interface.extent,
    };
}

pub fn fetchResources(self: *const Self, tpa: std.mem.Allocator, frame_data: *PerFrameData, render_graph: *const RenderGraph2.Desc, swapchain_textures: []const SwapchainTexture) !GraphResources {

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
                try frame_data.transient_buffers2.append(self.allocator, buffer);
                break :result BufferResource{
                    .interface = buffer.interface(),
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
                const texture = try Image.init2D(self.device, getTextureSize(desc.extent, textures[0..i]), .r8g8b8a8_unorm, .{ .storage_bit = true }, .gpu_only);
                try frame_data.transient_textures2.append(self.allocator, texture);
                break :result TextureResource{
                    .interface = texture.interface(),
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

pub fn getBufferStateAccess(access: RenderGraph2.BufferAccess) BufferStateAccess {
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
    src_access: RenderGraph2.BufferAccess,
    dst_access: RenderGraph2.BufferAccess,
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

pub fn getTextureStateAccess(access: RenderGraph2.TextureAccess, is_color: bool, unifined_image_layout: bool) TextureStateAccess {
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
    texture: Image.Interface,
    src_access: RenderGraph2.TextureAccess,
    dst_access: RenderGraph2.TextureAccess,
) ?vk.ImageMemoryBarrier2 {
    const aspect_mask = Image.getFormatAspectMask(texture.format);
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
    render_graph: *const RenderGraph2.Desc,
    pass: RenderGraph2.Compiled.CompiledPass,
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

        for (pass_dependency.dependecies.items) |dependency| {
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
    desc: *const RenderGraph2.Desc,
    compiled: *const RenderGraph2.Compiled,
    resources: *const GraphResources,
    swapchain_textures: []const SwapchainTexture,
) !void {
    const fence = try frame_data.fence_pool.get();
    try frame_data.frame_wait_fences.append(self.allocator, fence);

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
            var src_access: RenderGraph2.TextureAccess = .none;

            if (desc.textures.items[swapchain_texture.resource.idx].last_useage) |pass| {
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

pub fn submitRenderGraph(self: *Self, tpa: std.mem.Allocator, render_graph: *const RenderGraph2.Desc) !void {
    const TIMEOUT_NS: u64 = std.time.ns_per_s * 5;

    //Compile graph
    var compiled: RenderGraph2.Compiled = try .compile(tpa, render_graph);
    defer compiled.deinit(tpa);

    const frame_data = self.getNextFrameData();

    //Wait for previous frame to finish
    if (!frame_data.waitForPrevious(self.device.proxy, TIMEOUT_NS)) {
        std.log.err("Failed to wait for previous frame fences", .{});
    }

    // Clear old graph tranisent data
    // TODO: remove once old graph is removed
    {
        for (frame_data.transient_buffers.items) |handle| {
            self.destroyBuffer(handle);
        }

        for (frame_data.transient_images.items) |handle| {
            self.destroyImage(handle);
        }
    }

    frame_data.reset();
    errdefer frame_data.errorReset(self.device.proxy);

    // Swapchain Images
    const swapchain_textures = try tpa.alloc(SwapchainTexture, render_graph.window_textures.items.len);
    defer tpa.free(swapchain_textures);

    for (render_graph.window_textures.items, swapchain_textures) |window, *swapchain_texture| {
        const surface_swapchain = self.swapchains.getPtr(window.handle) orelse return error.InvalidWindow;
        var swapchain = surface_swapchain.swapchain;

        if (swapchain.out_of_date) {
            _ = self.device.proxy.deviceWaitIdle() catch {};
            const window_size = window.handle.getSize();
            const new_swapchain = try Swapchain.init(
                self.device,
                surface_swapchain.surface,
                .{ .width = window_size[0], .height = window_size[1] },
                swapchain.settings,
                swapchain.handle,
            );
            swapchain.deinit();
            swapchain.* = new_swapchain;
        }

        const wait_semaphore = try frame_data.semaphore_pool.get();
        const swapchain_image = swapchain.acquireNextImage(null, wait_semaphore, .null_handle) catch |err| {
            if (err == error.OutOfDateKHR) {
                swapchain.out_of_date = true;
            }
            return err;
        };

        swapchain_texture.* = .{
            .swapchain = surface_swapchain.swapchain,
            .index = swapchain_image.index,
            .interface = swapchain_image.image,
            .wait_semaphore = wait_semaphore,
            .present_semaphore = swapchain_image.present_semaphore,
            .resource = window.texture,
        };
    }

    //Fetch resources + states
    const resources = try self.fetchResources(tpa, frame_data, render_graph, swapchain_textures);

    //Record command buffers
    try self.recordRenderGraph(tpa, frame_data, render_graph, &compiled, &resources, swapchain_textures);

    //Submit command buffers

    //Submit Presents
    for (swapchain_textures) |swapchain_info| {
        swapchain_info.swapchain.queuePresent(
            self.device.graphics_queue.handle,
            swapchain_info.index,
            swapchain_info.present_semaphore,
        ) catch |err| {
            switch (err) {
                error.OutOfDateKHR => swapchain_info.swapchain.out_of_date = true,
                else => return err,
            }
        };
    }

    //Update last usages
}

// *************************************************************************************************************************
// Old Graph code starts here
// *************************************************************************************************************************
// TODO: replace with new code

const SwapchainTexture = struct {
    swapchain: *Swapchain,
    index: u32,
    interface: Image.Interface,
    wait_semaphore: vk.Semaphore,
    present_semaphore: vk.Semaphore,
    resource: RenderGraph2.Texture,
};

const UploadInfo = struct {
    src_offset: usize,
    bytes_written: usize,
};

pub fn render(self: *Self, temp_allocator: std.mem.Allocator, render_graph: rg.RenderGraph) !void {
    const TIMEOUT_NS: u64 = std.time.ns_per_s * 5;

    const frame_data = self.getNextFrameData();

    //Wait for previous frame to finish
    if (!frame_data.waitForPrevious(self.device.proxy, TIMEOUT_NS)) {
        std.log.err("Failed to wait for previous frame fences", .{});
    }

    //Clear tranisent data
    for (frame_data.transient_buffers.items) |handle| {
        self.destroyBuffer(handle);
    }

    for (frame_data.transient_images.items) |handle| {
        self.destroyImage(handle);
    }
    frame_data.reset();
    errdefer frame_data.errorReset(self.device.proxy);

    const fence = try frame_data.fence_pool.get();
    try frame_data.frame_wait_fences.append(self.allocator, fence);

    // Swapchain Images
    const swapchain_infos = try temp_allocator.alloc(SwapchainTexture, render_graph.swapchains.items.len);
    defer temp_allocator.free(swapchain_infos);

    for (render_graph.swapchains.items, swapchain_infos) |window, *swapchain_info| {
        const surface_swapchain = self.swapchains.getPtr(window) orelse return error.InvalidWindow;
        var swapchain = surface_swapchain.swapchain;

        if (swapchain.out_of_date) {
            _ = self.device.proxy.deviceWaitIdle() catch {};
            const window_size = window.getSize();
            const new_swapchain = try Swapchain.init(
                self.device,
                surface_swapchain.surface,
                .{ .width = window_size[0], .height = window_size[1] },
                swapchain.settings,
                swapchain.handle,
            );
            swapchain.deinit();
            swapchain.* = new_swapchain;
        }

        const wait_semaphore = try frame_data.semaphore_pool.get();
        const swapchain_image = swapchain.acquireNextImage(null, wait_semaphore, .null_handle) catch |err| {
            if (err == error.OutOfDateKHR) {
                swapchain.out_of_date = true;
            }
            return err;
        };

        swapchain_info.* = .{
            .swapchain = surface_swapchain.swapchain,
            .index = swapchain_image.index,
            .interface = swapchain_image.image,
            .wait_semaphore = wait_semaphore,
            .present_semaphore = swapchain_image.present_semaphore,
            .resource = undefined,
        };
    }

    //Resources
    const buffers = try temp_allocator.alloc(Buffer.Interface, render_graph.buffers.items.len);
    defer temp_allocator.free(buffers);

    const images = try temp_allocator.alloc(Image.Interface, render_graph.textures.items.len);
    defer temp_allocator.free(images);

    // Transient Buffers
    try frame_data.transient_buffers.resize(self.allocator, render_graph.transient_buffers.items.len);

    for (buffers, render_graph.buffers.items) |*buffer, rg_buffer| {
        buffer.* = switch (rg_buffer) {
            .persistent => |handle| self.buffers.get(handle).?.buffer.interface(),
            .transient => |transient_index| buf: {
                const transient_desc = render_graph.transient_buffers.items[transient_index];
                frame_data.transient_buffers.items[transient_index] = try self.createBuffer("transient_buffer", transient_desc.size, transient_desc.usage);
                break :buf self.buffers.get(frame_data.transient_buffers.items[transient_index]).?.buffer.interface();
            },
        };
    }

    // Transient Images
    try frame_data.transient_images.resize(self.allocator, render_graph.transient_textures.items.len);

    for (images, render_graph.textures.items, 0..) |*image, rg_texture, i| {
        image.* = switch (rg_texture) {
            .persistent => |handle| self.images.get(handle).?.texture.interface(),
            .swapchain => |index| img: {
                swapchain_infos[index].resource = .{ .idx = @intCast(i) };
                break :img swapchain_infos[index].interface;
            },
            .transient => |transient_index| img: {
                // This currently relies on the fact that transient textures can only referance a RenderGraphImage that was create before this one,
                // therefor ealier in the list and already filled in the array.
                const transient_desc = render_graph.transient_textures.items[transient_index];
                const extent: vk.Extent2D = switch (transient_desc.extent) {
                    .fixed => |extent| extent,
                    .relative => |r| images[r.index].extent,
                };
                frame_data.transient_images.items[transient_index] = try self.createImage(.{ extent.width, extent.height }, transient_desc.format, transient_desc.usage);
                break :img self.images.get(frame_data.transient_images.items[transient_index]).?.texture.interface();
            },
        };
    }

    const resources = rg.Resources{
        .buffers = buffers,
        .textures = images,
    };

    try self.bindless_descriptor.write_updates(temp_allocator);

    const command_buffer_handle = try frame_data.graphics_command_pool.get();
    const command_buffer = vk.CommandBufferProxy.init(command_buffer_handle, self.device.proxy.wrapper);

    try command_buffer.beginCommandBuffer(&.{});
    self.bindless_descriptor.bind(command_buffer, self.bindless_layout);

    if (try frame_data.transfer_queue.createRenderPass(temp_allocator)) |render_pass| {
        //TODO: Replace this very bad barrier
        {
            const memory_barriers: []const vk.MemoryBarrier2 = &.{
                .{
                    .src_stage_mask = .{ .all_commands_bit = true },
                    .src_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                    .dst_stage_mask = .{ .all_commands_bit = true },
                    .dst_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                },
            };
            command_buffer.pipelineBarrier2(&.{
                .memory_barrier_count = @intCast(memory_barriers.len),
                .p_memory_barriers = memory_barriers.ptr,
            });
        }

        if (render_pass.build_fn) |build_fn| {
            build_fn(render_pass.build_data, self, resources, command_buffer, null);
        }
    }

    //Data upload
    if (render_graph.buffer_upload_passes.items.len != 0) {
        const buffer_upload_infos = try temp_allocator.alloc(UploadInfo, render_graph.buffer_upload_passes.items.len);
        defer temp_allocator.free(buffer_upload_infos);

        var total_upload_size: usize = 0;
        for (buffer_upload_infos, render_graph.buffer_upload_passes.items) |*info, upload| {
            info.* = .{ .src_offset = total_upload_size, .bytes_written = 0 };
            total_upload_size += upload.size;
        }

        if (frame_data.upload_src_buffer) |upload_buffer| {
            if (upload_buffer.size < total_upload_size) {
                upload_buffer.deinit();
                frame_data.upload_src_buffer = null;
            }
        }

        if (frame_data.upload_src_buffer == null) {
            frame_data.upload_src_buffer = try Buffer.init(self.device, total_upload_size, .{ .transfer_src_bit = true }, .cpu_only);
        }

        const upload_buffer = &frame_data.upload_src_buffer.?;
        const upload_src_slice = upload_buffer.allocation.getMappedByteSlice().?;

        for (buffer_upload_infos, render_graph.buffer_upload_passes.items) |*info, upload| {
            const start = info.src_offset;
            const end = start + upload.size;
            info.bytes_written = upload.write_fn(upload.write_data, upload.write_data_len, upload_src_slice[start..end]);
        }

        //TODO: Replace this very bad barrier
        {
            const memory_barriers: []const vk.MemoryBarrier2 = &.{
                .{
                    .src_stage_mask = .{ .all_commands_bit = true },
                    .src_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                    .dst_stage_mask = .{ .all_commands_bit = true },
                    .dst_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                },
            };
            command_buffer.pipelineBarrier2(&.{
                .memory_barrier_count = @intCast(memory_barriers.len),
                .p_memory_barriers = memory_barriers.ptr,
            });
        }

        for (buffer_upload_infos, render_graph.buffer_upload_passes.items) |info, upload| {
            const dst = buffers[upload.target.index];

            var write_size = info.bytes_written;
            if (dst.size < upload.offset + upload.size) {
                std.log.err(
                    "Buffer upload too large clamping: Buffer Offset: {} Buffer Size: {} Max Write: {}, Written Size: {}",
                    .{
                        upload.offset,
                        dst.size,
                        upload.size,
                        info.bytes_written,
                    },
                );
                const total_possible_write = dst.size - upload.offset;
                write_size = @max(write_size, total_possible_write);
            }

            if (write_size != 0) {
                const region = vk.BufferCopy{
                    .src_offset = info.src_offset,
                    .dst_offset = upload.offset,
                    .size = write_size,
                };
                command_buffer.copyBuffer(upload_buffer.handle, dst.handle, 1, @ptrCast(&region));
            }
        }
    }

    for (render_graph.render_passes.items) |render_pass| {
        if (self.device.debug) {
            const temp_name: [:0]const u8 = try temp_allocator.dupeZ(u8, render_pass.name);
            command_buffer.beginDebugUtilsLabelEXT(&.{
                .p_label_name = temp_name,
                .color = .{ 1.0, 0.0, 0.0, 1.0 },
            });
        }
        defer if (self.device.debug) {
            command_buffer.endDebugUtilsLabelEXT();
        };

        var render_extent: ?vk.Extent2D = null;

        if (render_pass.raster_pass) |raster_pass| {
            var image_barriers: std.ArrayList(vk.ImageMemoryBarrier2) = try .initCapacity(temp_allocator, raster_pass.color_attachments.items.len + 1);
            defer image_barriers.deinit(temp_allocator);

            const color_attachments = try temp_allocator.alloc(vk.RenderingAttachmentInfo, raster_pass.color_attachments.items.len);
            defer temp_allocator.free(color_attachments);

            for (color_attachments, raster_pass.color_attachments.items) |*vk_attachment, attachment| {
                const interface = &images[attachment.texture.index];

                if (interface.transitionLazy(.color_attachment_optimal)) |barrier| {
                    image_barriers.appendAssumeCapacity(barrier);
                }

                if (render_extent) |extent| {
                    if (extent.width != interface.extent.width or extent.height != interface.extent.height) {
                        return error.AttachmentsExtentDoNoMatch;
                    }
                } else {
                    render_extent = interface.extent;
                }

                vk_attachment.* = .{
                    .image_view = interface.view_handle,
                    .image_layout = .color_attachment_optimal,
                    .resolve_mode = .{},
                    .resolve_image_layout = .undefined,
                    .load_op = if (attachment.clear != null) .clear else .load,
                    .store_op = if (attachment.store) .store else .dont_care,
                    .clear_value = .{ .color = attachment.clear orelse undefined },
                };
            }

            var depth_attachment: ?vk.RenderingAttachmentInfo = null;
            if (raster_pass.depth_attachment) |attachment| {
                const interface = &images[attachment.texture.index];

                if (interface.transitionLazy(.depth_attachment_stencil_read_only_optimal)) |barrier| {
                    image_barriers.appendAssumeCapacity(barrier);
                }

                if (render_extent) |extent| {
                    if (extent.width != interface.extent.width or extent.height != interface.extent.height) {
                        return error.AttachmentsExtentDoNoMatch;
                    }
                } else {
                    render_extent = interface.extent;
                }

                depth_attachment = .{
                    .image_view = interface.view_handle,
                    .image_layout = .depth_attachment_stencil_read_only_optimal,
                    .resolve_mode = .{},
                    .resolve_image_layout = .undefined,
                    .load_op = if (attachment.clear != null) .clear else .load,
                    .store_op = if (attachment.store) .store else .dont_care,
                    .clear_value = .{ .depth_stencil = .{ .depth = attachment.clear orelse undefined, .stencil = 0 } },
                };
            }

            //TODO: Replace this very bad barrier
            {
                command_buffer.pipelineBarrier2(&.{
                    .image_memory_barrier_count = @intCast(image_barriers.items.len),
                    .p_image_memory_barriers = image_barriers.items.ptr,
                });
            }

            const render_area: vk.Rect2D = .{ .extent = render_extent.?, .offset = .{ .x = 0, .y = 0 } };
            const rendering_info: vk.RenderingInfo = .{
                .render_area = render_area,
                .layer_count = 1,
                .view_mask = 0,
                .color_attachment_count = @intCast(color_attachments.len),
                .p_color_attachments = color_attachments.ptr,
                .p_depth_attachment = if (depth_attachment) |attachment| @ptrCast(&attachment) else null,
            };
            command_buffer.beginRendering(&rendering_info);

            const viewport: vk.Viewport = .{
                .width = @floatFromInt(render_area.extent.width),
                .height = @floatFromInt(render_area.extent.height),
                .x = 0.0,
                .y = 0.0,
                .min_depth = 0.0,
                .max_depth = 1.0,
            };
            command_buffer.setViewport(0, 1, @ptrCast(&viewport));
            command_buffer.setScissor(0, 1, @ptrCast(&render_area));
        } else {
            //TODO: Replace this very bad barrier
            const memory_barriers: []const vk.MemoryBarrier2 = &.{
                .{
                    .src_stage_mask = .{ .all_commands_bit = true },
                    .src_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                    .dst_stage_mask = .{ .all_commands_bit = true },
                    .dst_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                },
            };
            command_buffer.pipelineBarrier2(&.{
                .memory_barrier_count = @intCast(memory_barriers.len),
                .p_memory_barriers = memory_barriers.ptr,
            });
        }

        if (render_pass.build_fn) |build_fn| {
            build_fn(render_pass.build_data, self, resources, command_buffer, render_extent);
        }

        if (render_pass.raster_pass != null) {
            command_buffer.endRendering();
        }
    }

    //Transitioning Swapchains to final formats
    {
        const swapchain_transitions = try temp_allocator.alloc(vk.ImageMemoryBarrier2, swapchain_infos.len);
        defer temp_allocator.free(swapchain_transitions);

        for (swapchain_infos, swapchain_transitions) |swapchain_info, *memory_barrier| {
            memory_barrier.* = .{
                .image = swapchain_info.interface.handle,
                .old_layout = resources.textures[swapchain_info.resource.idx].layout,
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

    const wait_semaphores = try temp_allocator.alloc(vk.Semaphore, swapchain_infos.len);
    defer temp_allocator.free(wait_semaphores);

    const wait_dst_stage_masks = try temp_allocator.alloc(vk.PipelineStageFlags, swapchain_infos.len);
    defer temp_allocator.free(wait_dst_stage_masks);

    const signal_semaphores = try temp_allocator.alloc(vk.Semaphore, swapchain_infos.len);
    defer temp_allocator.free(signal_semaphores);

    for (swapchain_infos, 0..) |swapchain_info, i| {
        wait_semaphores[i] = swapchain_info.wait_semaphore;
        wait_dst_stage_masks[i] = wait_dst_stage_mask;
        signal_semaphores[i] = swapchain_info.present_semaphore;
    }

    const submit_infos: [1]vk.SubmitInfo = .{vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = (&command_buffer_handle)[0..1],
        .wait_semaphore_count = @intCast(wait_semaphores.len),
        .p_wait_semaphores = wait_semaphores.ptr,
        .p_wait_dst_stage_mask = wait_dst_stage_masks.ptr,
        .signal_semaphore_count = @intCast(signal_semaphores.len),
        .p_signal_semaphores = signal_semaphores.ptr,
    }};

    try self.device.proxy.queueSubmit(self.device.graphics_queue.handle, @intCast(submit_infos.len), &submit_infos, fence);

    for (swapchain_infos) |swapchain_info| {
        swapchain_info.swapchain.queuePresent(
            self.device.graphics_queue.handle,
            swapchain_info.index,
            swapchain_info.present_semaphore,
        ) catch |err| {
            switch (err) {
                error.OutOfDateKHR => swapchain_info.swapchain.out_of_date = true,
                else => return err,
            }
        };
    }
}

pub fn calcDeviceScore(instance: *const Instance, p_device: Instance.PhysicalDevice) ?usize {
    _ = instance; // autofix
    var score: usize = 0;

    if (p_device.info.type == .cpu) {
        return null;
    }

    if (p_device.info.type == .discrete_gpu) {
        score += 100;
    }

    if (p_device.info.extensions.mesh_shader_support) {
        score += 50;
    }

    return score;
}
