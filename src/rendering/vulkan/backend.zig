const std = @import("std");

const vk = @import("vulkan");

const HandlePool = @import("../../containers.zig").HandlePool;
const sdl3 = @import("../../platform/sdl3.zig");
const Vulkan = sdl3.Vulkan;
const Window = sdl3.Window;
const BindlessDescriptor = @import("bindless_descriptor.zig");
const Buffer = @import("buffer.zig");
const Device = @import("device.zig");
const Image = @import("image.zig");
const Instance = @import("instance.zig");
const RenderGraphDefinition = @import("render_graph.zig").RenderGraphDefinition;
const Sampler = @import("sampler.zig");
const Swapchain = @import("swapchain.zig");

const BufferPool = HandlePool(Buffer);
const ImagePool = HandlePool(Image);
pub const BufferHandle = BufferPool.Handle;
pub const ImageHandle = ImagePool.Handle;

const SurfaceSwapchain = struct {
    surface: vk.SurfaceKHR,
    swapchain: *Swapchain,
};

const Self = @This();

allocator: std.mem.Allocator,
instance: Instance,
device: *Device,
bindless_descriptor: *BindlessDescriptor,
bindless_layout: vk.PipelineLayout,

swapchains: std.AutoArrayHashMap(Window, SurfaceSwapchain),

buffers: BufferPool,
images: ImagePool,
linear_sampler: Sampler,

pub fn init(allocator: std.mem.Allocator, frames_in_flight_count: u8) !Self {
    if (frames_in_flight_count == 0) {
        return error.InvalidFramesInFlightCount;
    }

    const instance = try Instance.init(allocator, Vulkan.getProcInstanceFunction().?, Vulkan.getInstanceExtensions(), .{ .name = "Saturn Engine", .version = Instance.makeVersion(0, 0, 0, 1) });
    errdefer instance.deinit();

    var device = try allocator.create(Device);
    errdefer allocator.destroy(device);

    device.* = try instance.createDevice(0);
    errdefer device.deinit();

    var bindless_descriptor = try allocator.create(BindlessDescriptor);
    errdefer allocator.destroy(bindless_descriptor);

    bindless_descriptor.* = try BindlessDescriptor.init(device, .{
        .uniform_buffers = 1024,
        .storage_buffers = 1024,
        .sampled_images = 1024,
        .storage_images = 1024,
    });
    errdefer bindless_descriptor.deinit();

    //TODO: add flags when RTX-Shaders or Mesh-Shading are enabled
    const All_STAGE_FLAGS = vk.ShaderStageFlags{
        .vertex_bit = true,
        .fragment_bit = true,
        .compute_bit = true,
    };

    const bindless_layout = try device.device.createPipelineLayout(&.{
        .set_layout_count = 1,
        .p_set_layouts = (&bindless_descriptor.layout)[0..1],
        .push_constant_range_count = 1,
        .p_push_constant_ranges = (&vk.PushConstantRange{
            .stage_flags = All_STAGE_FLAGS,
            .offset = 0,
            .size = 256,
        })[0..1],
    }, null);
    errdefer device.device.destroyPipelineLayout(bindless_layout, null);

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
    };
}

pub fn deinit(self: *Self) void {
    for (self.swapchains.values()) |surface_swapchain| {
        surface_swapchain.swapchain.deinit();
        Vulkan.destroySurface(self.instance.instance.handle, surface_swapchain.surface, null);
    }
    self.swapchains.deinit();

    self.linear_sampler.deinit();
    self.buffers.deinit_with_entries();
    self.images.deinit_with_entries();

    self.device.device.destroyPipelineLayout(self.bindless_layout, null);
    self.bindless_descriptor.deinit();
    self.allocator.destroy(self.bindless_descriptor);
    self.device.deinit();
    self.allocator.destroy(self.device);
    self.instance.deinit();
}

pub fn claimWindow(self: *Self, window: Window) !void {
    const surface = Vulkan.createSurface(self.instance.instance.handle, window, null).?;
    errdefer Vulkan.destroySurface(self.instance.instance.handle, surface, null);

    const window_size = window.getSize();
    const swapchain = try self.allocator.create(Swapchain);
    errdefer self.allocator.destroy(swapchain);

    swapchain.* = try Swapchain.init(self.device, surface, .{ .width = window_size[0], .height = window_size[1] }, null);
    errdefer swapchain.deinit();

    try self.swapchains.put(window, .{ .surface = surface, .swapchain = swapchain });
}

pub fn releaseWindow(self: *Self, window: Window) void {
    if (self.swapchains.fetchSwapRemove(window)) |entry| {
        entry.value.swapchain.deinit();
        Vulkan.destroySurface(self.instance.instance.handle, entry.value.surface, null);
        self.allocator.destroy(entry.value.swapchain);
    }
}

pub fn createBuffer(self: *Self, size: usize, usage: vk.BufferUsageFlags) !BufferPool.Handle {
    const buffer: Buffer = try .init(self.device, size, usage, .gpu_only);
    errdefer buffer.deinit();

    //TOOD: buffer bindings

    return self.buffers.insert(buffer);
}
pub fn createBufferWithData(self: *Self, usage: vk.BufferUsageFlags, data: []const u8) !BufferPool.Handle {
    var buffer: Buffer = try .init(self.device, data.len, usage, .gpu_only);
    errdefer buffer.deinit();

    if (buffer.allocation.mapped_ptr) |buffer_ptr| {
        const buffer_slice_ptr: [*]u8 = @ptrCast(@alignCast(buffer_ptr));
        const buffer_slice: []u8 = buffer_slice_ptr[0..data.len];
        @memcpy(buffer_slice, data);
    } else {
        //TODO: slow transfer upload
        try buffer.uploadBufferData(self.device, self.device.graphics_queue, data);
    }

    return self.buffers.insert(buffer);
}
pub fn destroyBuffer(self: *Self, handle: BufferPool.Handle) void {
    if (self.buffers.remove(handle)) |buffer| {
        buffer.deinit(); //TODO: delete after buffer has left pipeline
    } else {
        std.log.err("Invalid Buffer Handle: {}", .{handle});
    }
}

pub fn createImage(self: *Self, size: [2]u32, format: vk.Format, usage: vk.ImageUsageFlags) !ImagePool.Handle {
    var image: Image = try .init2D(self.device, .{ .width = size[0], .height = size[1] }, format, usage, .gpu_only);
    errdefer image.deinit();

    //TOOD: image bindings
    if (usage.contains(.{ .sampled_bit = true })) {
        image.sampled_binding = self.bindless_descriptor.bindSampledImage(image, self.linear_sampler);
    }

    return self.images.insert(image);
}
pub fn createImageWithData(self: *Self, size: [2]u32, format: vk.Format, usage: vk.ImageUsageFlags, data: []const u8) !ImagePool.Handle {
    var image: Image = try .init2D(self.device, .{ .width = size[0], .height = size[1] }, format, usage, .gpu_only);
    errdefer image.deinit();

    //TODO: use host_image_copy if avalible
    try image.uploadImageData(self.device, self.device.graphics_queue, .shader_read_only_optimal, data);

    return self.images.insert(image);
}
pub fn destroyImage(self: *Self, handle: ImagePool.Handle) void {
    if (self.images.remove(handle)) |image| {
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
    last_layout: vk.ImageLayout = .undefined,
};

pub fn render(self: *Self, temp_allocator: std.mem.Allocator, render_graph: RenderGraphDefinition) !void {
    const fence = try self.device.device.createFence(&.{}, null);
    defer self.device.device.destroyFence(fence, null);

    // Swapchain Images
    const swapchain_infos = try temp_allocator.alloc(SwapchainImageInfo, render_graph.swapchains.items.len);
    defer temp_allocator.free(swapchain_infos);
    defer for (swapchain_infos) |swapchain_info| {
        defer self.device.device.destroySemaphore(swapchain_info.wait_semaphore, null);
        defer self.device.device.destroySemaphore(swapchain_info.present_semaphore, null);
    };

    for (render_graph.swapchains.items, swapchain_infos) |window, *swapchain_info| {
        const surface_swapchain = self.swapchains.getPtr(window) orelse return error.InvalidWindow;
        var swapchain = surface_swapchain.swapchain;

        if (swapchain.out_of_date) {
            std.log.info("Rebuilding Swapchain", .{});
            //_ = self.device.device.deviceWaitIdle() catch {};
            const window_size = window.getSize();
            const new_swapchain = try Swapchain.init(
                self.device,
                surface_swapchain.surface,
                .{ .width = window_size[0], .height = window_size[1] },
                swapchain.handle,
            );
            swapchain.deinit();
            swapchain.* = new_swapchain;
        }

        const wait_semaphore = try self.device.device.createSemaphore(&.{}, null);
        const present_semaphore = try self.device.device.createSemaphore(&.{}, null);
        const swapchain_image = try swapchain.acquireNextImage(null, wait_semaphore, .null_handle);

        swapchain_info.* = .{
            .swapchain = surface_swapchain.swapchain,
            .index = swapchain_image.index,
            .image = swapchain_image.image,
            .wait_semaphore = wait_semaphore,
            .present_semaphore = present_semaphore,
        };
    }

    //Resources
    const images = try temp_allocator.alloc(Image.Interface, render_graph.textures.items.len);
    defer temp_allocator.free(images);

    // Transient Images
    const transient_images = try temp_allocator.alloc(ImageHandle, render_graph.transient_textures.items.len);
    defer temp_allocator.free(transient_images);
    defer for (transient_images) |transient_image| {
        self.destroyImage(transient_image);
    };

    for (images, render_graph.textures.items) |*image, texture| {
        image.* = switch (texture) {
            .persistent => |handle| self.images.get(handle).?.interface(),
            .swapchain => |index| swapchain_infos[index].image,
            .transient => |transient_index| img: {
                // This currently relies on the fact that transient textures can only referance a RenderGraphImage that was create before this one,
                // therefor ealier in the list and already filled in the array.
                const transient_desc = render_graph.transient_textures.items[transient_index];
                const extent: vk.Extent2D = switch (transient_desc.extent) {
                    .fixed => |extent| extent,
                    .relative => |r| images[r.texture_index].extent,
                };
                transient_images[transient_index] = try self.createImage(.{ extent.width, extent.height }, transient_desc.format, transient_desc.usage);
                break :img self.images.get(transient_images[transient_index]).?.interface();
            },
        };
    }

    var command_buffers: [1]vk.CommandBuffer = undefined;
    try self.device.device.allocateCommandBuffers(&.{ .command_buffer_count = @intCast(command_buffers.len), .command_pool = self.device.graphics_queue.command_pool, .level = .primary }, &command_buffers);
    defer self.device.device.freeCommandBuffers(self.device.graphics_queue.command_pool, @intCast(command_buffers.len), &command_buffers);

    const command_buffer_handle = command_buffers[0];
    const command_buffer = vk.CommandBufferProxy.init(command_buffer_handle, self.device.device.wrapper);

    try command_buffer.beginCommandBuffer(&.{});
    self.bindless_descriptor.bind(command_buffer, self.bindless_layout);

    //TODO: render here
    for (render_graph.render_passes.items) |render_pass| {
        var render_extent: ?vk.Extent2D = null;

        if (render_pass.raster_pass) |raster_pass| {
            var image_barriers: std.ArrayList(vk.ImageMemoryBarrier) = try .initCapacity(temp_allocator, raster_pass.color_attachments.len + 1);
            defer image_barriers.deinit();

            const color_attachments = try temp_allocator.alloc(vk.RenderingAttachmentInfo, raster_pass.color_attachments.len);
            defer temp_allocator.free(color_attachments);

            for (color_attachments, raster_pass.color_attachments) |*vk_attachment, attachment| {
                const interface = &images[attachment.texture.texture_index];

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
                const interface = &images[attachment.texture.texture_index];

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

            command_buffer.pipelineBarrier(
                .{ .all_commands_bit = true },
                .{ .all_commands_bit = true },
                .{},
                0,
                null,
                0,
                null,
                @intCast(image_barriers.items.len),
                image_barriers.items.ptr,
            );

            command_buffer.beginRendering(&.{
                .render_area = .{ .extent = render_extent.?, .offset = .{ .x = 0, .y = 0 } },
                .layer_count = 1,
                .view_mask = 0,
                .color_attachment_count = @intCast(color_attachments.len),
                .p_color_attachments = color_attachments.ptr,
                .p_depth_attachment = if (depth_attachment) |attachment| @ptrCast(&attachment) else null,
            });
        }

        if (render_pass.build_fn) |build_fn| {
            build_fn(self, command_buffer, render_extent, render_pass.build_data);
        }

        if (render_pass.raster_pass != null) {
            command_buffer.endRendering();
        }
    }

    //Transitioning Swapchains to final formats
    {
        const swapchain_transitions = try temp_allocator.alloc(vk.ImageMemoryBarrier, swapchain_infos.len);
        defer temp_allocator.free(swapchain_transitions);

        for (swapchain_infos, swapchain_transitions) |swapchain_info, *memory_barrier| {
            memory_barrier.* = .{
                .image = swapchain_info.image.handle,
                .old_layout = swapchain_info.last_layout,
                .new_layout = .present_src_khr,
                .src_access_mask = .{},
                .dst_access_mask = .{},
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

        command_buffer.pipelineBarrier(
            .{ .all_commands_bit = true },
            .{ .all_commands_bit = true },
            .{},
            0,
            null,
            0,
            null,
            @intCast(swapchain_transitions.len),
            swapchain_transitions.ptr,
        );
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
        .command_buffer_count = @intCast(command_buffers.len),
        .p_command_buffers = &command_buffers,
        .wait_semaphore_count = @intCast(wait_semaphores.len),
        .p_wait_semaphores = wait_semaphores.ptr,
        .p_wait_dst_stage_mask = wait_dst_stage_masks.ptr,
        .signal_semaphore_count = @intCast(signal_semaphores.len),
        .p_signal_semaphores = signal_semaphores.ptr,
    }};

    try self.device.device.queueSubmit(self.device.graphics_queue.handle, @intCast(submit_infos.len), &submit_infos, fence);

    for (swapchain_infos) |swapchain_info| {
        try swapchain_info.swapchain.queuePresent(
            self.device.graphics_queue.handle,
            swapchain_info.index,
            swapchain_info.present_semaphore,
        );
    }

    _ = try self.device.device.waitForFences(1, @ptrCast(&fence), 1, std.math.maxInt(u64));
    _ = self.device.device.queueWaitIdle(self.device.graphics_queue.handle) catch {};
}
