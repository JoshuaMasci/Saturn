const std = @import("std");

const vk = @import("vulkan");

const HandlePool = @import("../../containers.zig").HandlePool;
const sdl3 = @import("../../platform/sdl3.zig");
const Vulkan = sdl3.Vulkan;
const Window = sdl3.Window;
const BindlessDescriptor = @import("bindless_descriptor.zig");
const Buffer = @import("buffer.zig");
const Image = @import("image.zig");
const Instance = @import("instance.zig");
const object_pools = @import("object_pools.zig");
const rg = @import("render_graph.zig");
pub const RenderGraph = rg.RenderGraph;
pub const RenderPass = rg.RenderPass;
const Sampler = @import("sampler.zig");
const Swapchain = @import("swapchain.zig");
const VkDevice = @import("vulkan_device.zig");

const BufferPool = HandlePool(Buffer);
const ImagePool = HandlePool(Image);
pub const BufferHandle = BufferPool.Handle;
pub const ImageHandle = ImagePool.Handle;

const SurfaceSwapchain = struct {
    surface: vk.SurfaceKHR,
    swapchain: *Swapchain,
};

const PerFrameData = struct {
    frame_wait_fences: std.ArrayList(vk.Fence),
    graphics_command_pool: object_pools.CommandBufferPool,
    semaphore_pool: object_pools.SemaphorePool,
    fence_pool: object_pools.FencePool,

    transient_buffers: std.ArrayList(BufferHandle),
    transient_images: std.ArrayList(ImageHandle),

    upload_src_buffer: ?Buffer = null,

    pub fn reset(self: *@This()) void {
        self.frame_wait_fences.clearRetainingCapacity();
        self.graphics_command_pool.reset();
        self.semaphore_pool.reset();
        self.fence_pool.reset();
        self.transient_buffers.clearRetainingCapacity();
        self.transient_images.clearRetainingCapacity();
    }
};

const Self = @This();

allocator: std.mem.Allocator,
instance: Instance,
device: *VkDevice,
bindless_descriptor: *BindlessDescriptor,
bindless_layout: vk.PipelineLayout,

swapchains: std.AutoArrayHashMap(Window, SurfaceSwapchain),

buffers: BufferPool,
images: ImagePool,
linear_sampler: Sampler,

frame_index: usize = 0,
frame_data: []PerFrameData,

pub fn init(allocator: std.mem.Allocator, frames_in_flight_count: u8) !Self {
    if (frames_in_flight_count == 0) {
        return error.InvalidFramesInFlightCount;
    }

    const instance = try Instance.init(allocator, Vulkan.getProcInstanceFunction().?, Vulkan.getInstanceExtensions(), .{ .name = "Saturn Engine", .version = Instance.makeVersion(0, 0, 0, 1) });
    errdefer instance.deinit();

    std.log.info("Available Physical Devices:", .{});
    for (instance.physical_devices, 0..) |physical_device, i| {
        std.log.info("{}: {f}", .{ i, physical_device.info });
    }

    const device_index = 0; //TODO: select device rather than just assume 0 is good
    std.log.info("Picking Device {}: {s}", .{ device_index, instance.physical_devices[device_index].info.name });

    var device = try allocator.create(VkDevice);
    errdefer allocator.destroy(device);

    device.* = try instance.createDevice(device_index);
    errdefer device.deinit();

    var bindless_descriptor = try allocator.create(BindlessDescriptor);
    errdefer allocator.destroy(bindless_descriptor);

    const DESCRIPTOR_COUNT = 4096;
    bindless_descriptor.* = try BindlessDescriptor.init(allocator, device, .{
        .uniform_buffers = DESCRIPTOR_COUNT,
        .storage_buffers = DESCRIPTOR_COUNT * 4,
        .sampled_images = DESCRIPTOR_COUNT * 2,
        .storage_images = DESCRIPTOR_COUNT,
    });
    errdefer bindless_descriptor.deinit();

    //TODO: add flags when RTX-Shaders or Mesh-Shading are enabled
    const All_STAGE_FLAGS = vk.ShaderStageFlags{
        .vertex_bit = true,
        .fragment_bit = true,
        .compute_bit = true,
    };

    const bindless_layout = try device.proxy.createPipelineLayout(&.{
        .set_layout_count = 1,
        .p_set_layouts = (&bindless_descriptor.layout)[0..1],
        .push_constant_range_count = 1,
        .p_push_constant_ranges = (&vk.PushConstantRange{
            .stage_flags = All_STAGE_FLAGS,
            .offset = 0,
            .size = 256,
        })[0..1],
    }, null);
    errdefer device.proxy.destroyPipelineLayout(bindless_layout, null);

    const frame_data = try allocator.alloc(PerFrameData, @intCast(frames_in_flight_count));
    errdefer allocator.free(frame_data);

    for (frame_data) |*data| {
        data.* = .{
            .frame_wait_fences = .empty,
            .graphics_command_pool = try .init(allocator, device, device.graphics_queue),
            .semaphore_pool = .init(allocator, device, .binary, 0),
            .fence_pool = .init(allocator, device, .{}),
            .transient_buffers = .empty,
            .transient_images = .empty,
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
        data.frame_wait_fences.deinit(self.allocator);
        data.graphics_command_pool.deinit();
        data.semaphore_pool.deinit();
        data.fence_pool.deinit();
        data.transient_buffers.deinit(self.allocator);
        data.transient_images.deinit(self.allocator);

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
    self.buffers.deinit_with_entries();
    self.images.deinit_with_entries();

    self.device.proxy.destroyPipelineLayout(self.bindless_layout, null);
    self.bindless_descriptor.deinit();
    self.allocator.destroy(self.bindless_descriptor);
    self.device.deinit();
    self.allocator.destroy(self.device);
    self.instance.deinit();
}

pub fn waitIdle(self: *const Self) void {
    _ = self.device.proxy.deviceWaitIdle() catch {};
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

pub fn createBuffer(self: *Self, size: usize, usage: vk.BufferUsageFlags) !BufferPool.Handle {
    var buffer: Buffer = try .init(self.device, size, usage, if (self.device.physical_device.info.memory.direct_buffer_upload) .gpu_mappable else .gpu_only);
    errdefer buffer.deinit();

    if (usage.contains(.{ .uniform_buffer_bit = true })) {
        buffer.uniform_binding = self.bindless_descriptor.uniform_buffer_array.bind(buffer);
    }

    if (usage.contains(.{ .storage_buffer_bit = true })) {
        buffer.storage_binding = self.bindless_descriptor.storage_buffer_array.bind(buffer);
    }

    return self.buffers.insert(buffer);
}
pub fn createBufferWithData(self: *Self, usage: vk.BufferUsageFlags, data: []const u8) !BufferPool.Handle {
    var buffer: Buffer = try .init(self.device, data.len, usage, if (self.device.physical_device.info.memory.direct_buffer_upload) .gpu_mappable else .gpu_only);
    errdefer buffer.deinit();

    if (usage.contains(.{ .uniform_buffer_bit = true })) {
        buffer.uniform_binding = self.bindless_descriptor.uniform_buffer_array.bind(buffer);
    }

    if (usage.contains(.{ .storage_buffer_bit = true })) {
        buffer.storage_binding = self.bindless_descriptor.storage_buffer_array.bind(buffer);
    }

    if (buffer.allocation.getMappedByteSlice()) |buffer_slice| {
        std.debug.assert(buffer_slice.len >= data.len);
        @memcpy(buffer_slice[0..data.len], data);
    } else {
        //TODO: use transfer queue
        try buffer.uploadBufferData(self.device, self.device.graphics_queue, data);
    }

    return self.buffers.insert(buffer);
}
pub fn destroyBuffer(self: *Self, handle: BufferPool.Handle) void {
    if (self.buffers.remove(handle)) |buffer| {
        if (buffer.uniform_binding) |binding| {
            self.bindless_descriptor.uniform_buffer_array.clear(binding);
        }

        if (buffer.storage_binding) |binding| {
            self.bindless_descriptor.storage_buffer_array.clear(binding);
        }

        buffer.deinit(); //TODO: delete after buffer has left pipeline
    } else {
        std.log.err("Invalid Buffer Handle: {}", .{handle});
    }
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

    return self.images.insert(image);
}
pub fn createImageWithData(self: *Self, size: [2]u32, format: vk.Format, usage: vk.ImageUsageFlags, data: []const u8) !ImagePool.Handle {
    var usage_flags = usage;
    if (self.device.physical_device.info.extensions.host_image_copy) {
        usage_flags.host_transfer_bit = true;
    }

    var image: Image = try .init2D(self.device, .{ .width = size[0], .height = size[1] }, format, usage_flags, .gpu_only);
    errdefer image.deinit();

    if (usage.contains(.{ .sampled_bit = true })) {
        image.sampled_binding = self.bindless_descriptor.sampled_image_array.bind(image, self.linear_sampler);
    }

    if (usage.contains(.{ .storage_bit = true })) {
        image.storage_binding = self.bindless_descriptor.storage_image_array.bind(image, null);
    }

    if (self.device.physical_device.info.extensions.host_image_copy) {
        try image.hostImageCopy(self.device, .shader_read_only_optimal, data);
    } else {
        //TODO: use transfer queue
        try image.uploadImageData(self.device, self.device.graphics_queue, .shader_read_only_optimal, data);
    }

    return self.images.insert(image);
}
pub fn destroyImage(self: *Self, handle: ImagePool.Handle) void {
    if (self.images.remove(handle)) |image| {
        if (image.sampled_binding) |binding| {
            self.bindless_descriptor.sampled_image_array.clear(binding);
        }

        if (image.storage_binding) |binding| {
            self.bindless_descriptor.storage_image_array.clear(binding);
        }

        image.deinit(); //TODO: delete after image has left pipeline
    } else {
        std.log.err("Invalid Image Handle: {}", .{handle});
    }
}

const SwapchainImageInfo = struct {
    swapchain: *Swapchain,
    index: u32,
    image: Image.Interface,
    wait_semaphore: vk.Semaphore,
    present_semaphore: vk.Semaphore,
    resource_index: usize,
};

const UploadInfo = struct {
    src_offset: usize,
    bytes_written: usize,
};

pub fn render(self: *Self, temp_allocator: std.mem.Allocator, render_graph: rg.RenderGraph) !void {
    self.frame_index = @mod(self.frame_index + 1, self.frame_data.len);
    const frame_data = &self.frame_data[self.frame_index];

    //Wait for previous frame to finish
    if (frame_data.frame_wait_fences.items.len > 0) {
        _ = try self.device.proxy.waitForFences(@intCast(frame_data.frame_wait_fences.items.len), frame_data.frame_wait_fences.items.ptr, .true, std.math.maxInt(u64));
        frame_data.frame_wait_fences.clearRetainingCapacity();
    }

    //Clear tranisent data
    for (frame_data.transient_buffers.items) |handle| {
        self.destroyBuffer(handle);
    }

    for (frame_data.transient_images.items) |handle| {
        self.destroyImage(handle);
    }
    frame_data.reset();

    const fence = try frame_data.fence_pool.get();
    try frame_data.frame_wait_fences.append(self.allocator, fence);
    errdefer {
        self.device.proxy.resetFences(@intCast(frame_data.frame_wait_fences.items.len), frame_data.frame_wait_fences.items.ptr) catch |err| {
            std.log.err("Failed to reset frame_wait_fences: {}", .{err});
        };
        frame_data.frame_wait_fences.clearRetainingCapacity();
    }

    // Swapchain Images
    const swapchain_infos = try temp_allocator.alloc(SwapchainImageInfo, render_graph.swapchains.items.len);
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
            .image = swapchain_image.image,
            .wait_semaphore = wait_semaphore,
            .present_semaphore = swapchain_image.present_semaphore,
            .resource_index = undefined,
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
            .persistent => |handle| self.buffers.get(handle).?.interface(),
            .transient => |transient_index| buf: {
                const transient_desc = render_graph.transient_buffers.items[transient_index];
                frame_data.transient_buffers.items[transient_index] = try self.createBuffer(transient_desc.size, transient_desc.usage);
                break :buf self.buffers.get(frame_data.transient_buffers.items[transient_index]).?.interface();
            },
        };
    }

    // Transient Images
    try frame_data.transient_images.resize(self.allocator, render_graph.transient_textures.items.len);

    for (images, render_graph.textures.items, 0..) |*image, rg_texture, i| {
        image.* = switch (rg_texture) {
            .persistent => |handle| self.images.get(handle).?.interface(),
            .swapchain => |index| img: {
                swapchain_infos[index].resource_index = i;
                break :img swapchain_infos[index].image;
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
                break :img self.images.get(frame_data.transient_images.items[transient_index]).?.interface();
            },
        };
    }

    const resources = rg.Resources{
        .buffers = buffers,
        .textures = images,
    };

    const command_buffer_handle = try frame_data.graphics_command_pool.get();
    const command_buffer = vk.CommandBufferProxy.init(command_buffer_handle, self.device.proxy.wrapper);

    try command_buffer.beginCommandBuffer(&.{});
    self.bindless_descriptor.bind(command_buffer, self.bindless_layout);

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
            info.bytes_written = upload.write_fn(upload.write_data, upload_src_slice[start..end]);
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
                .image = swapchain_info.image.handle,
                .old_layout = resources.textures[swapchain_info.resource_index].layout,
                .new_layout = .present_src_khr,
                .src_stage_mask = .{ .all_commands_bit = true },
                .src_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_stage_mask = .{ .all_commands_bit = true },
                .dst_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
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
