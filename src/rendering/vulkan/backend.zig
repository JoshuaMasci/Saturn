const std = @import("std");

const vk = @import("vulkan");

const sdl3 = @import("../../platform/sdl3.zig");
const Vulkan = sdl3.Vulkan;
const Window = sdl3.Window;
const BindlessDescriptor = @import("bindless_descriptor.zig");
const Device = @import("device.zig");
const Instance = @import("instance.zig");
const Swapchain = @import("swapchain.zig");

const SurfaceSwapchain = struct {
    surface: vk.SurfaceKHR,
    swapchain: Swapchain,
};

const Self = @This();

allocator: std.mem.Allocator,
instance: Instance,
device: *Device,
bindless_descriptor: *BindlessDescriptor,
bindless_layout: vk.PipelineLayout,

swapchains: std.AutoArrayHashMap(Window, SurfaceSwapchain),

pub fn init(allocator: std.mem.Allocator) !Self {
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
    };
}

pub fn deinit(self: *Self) void {
    for (self.swapchains.values()) |surface_swapchain| {
        surface_swapchain.swapchain.deinit();
        Vulkan.destroySurface(self.instance.instance.handle, surface_swapchain.surface, null);
    }
    self.swapchains.deinit();

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
    const swapchain = try Swapchain.init(self.device, surface, .{ .width = window_size[0], .height = window_size[1] }, null);
    errdefer swapchain.deinit();

    try self.swapchains.put(window, .{ .surface = surface, .swapchain = swapchain });
}

pub fn releaseWindow(self: *Self, window: Window) void {
    if (self.swapchains.fetchSwapRemove(window)) |entry| {
        entry.value.swapchain.deinit();
        Vulkan.destroySurface(self.instance.instance.handle, entry.value.surface, null);
    }
}

pub const CommandBufferBuildFn = *const fn (
    data_ptr: ?*anyopaque,
    device: vk.DeviceProxy,
    command_buffer: vk.CommandBufferProxy,
    layout: vk.PipelineLayout,
    target_size: vk.Extent2D,
) void;

pub fn render(self: Self, window: Window, build_fn_opt: ?CommandBufferBuildFn, build_data: ?*anyopaque) !void {
    const surface_swapchain = self.swapchains.getPtr(window) orelse return;
    var swapchain = surface_swapchain.swapchain;

    const depth_image = try @import("image.zig").init2D(self.device, .{ swapchain.size.width, swapchain.size.height }, .d16_unorm, .{ .depth_stencil_attachment_bit = true }, .gpu_only);
    defer depth_image.deinit();

    const fence = try self.device.device.createFence(&.{}, null);
    defer self.device.device.destroyFence(fence, null);

    const wait_semaphore = try self.device.device.createSemaphore(&.{}, null);
    defer self.device.device.destroySemaphore(wait_semaphore, null);

    const present_semaphore = try self.device.device.createSemaphore(&.{}, null);
    defer self.device.device.destroySemaphore(present_semaphore, null);

    var command_buffers: [1]vk.CommandBuffer = undefined;
    try self.device.device.allocateCommandBuffers(&.{ .command_buffer_count = @intCast(command_buffers.len), .command_pool = self.device.graphics_queue.command_pool, .level = .primary }, &command_buffers);
    defer self.device.device.freeCommandBuffers(self.device.graphics_queue.command_pool, @intCast(command_buffers.len), &command_buffers);

    const swapchain_image = try swapchain.acquireNextImage(null, wait_semaphore, .null_handle);

    const command_buffer_handle = command_buffers[0];
    const command_buffer = vk.CommandBufferProxy.init(command_buffer_handle, self.device.device.wrapper);

    try command_buffer.beginCommandBuffer(&.{});

    self.bindless_descriptor.bind(command_buffer, self.bindless_layout);

    const image_barriers: []const vk.ImageMemoryBarrier = &.{
        .{
            .image = swapchain_image.image,
            .old_layout = .undefined,
            .new_layout = .color_attachment_optimal,
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
        },
        .{
            .image = depth_image.handle,
            .old_layout = .undefined,
            .new_layout = .depth_attachment_optimal,
            .src_access_mask = .{},
            .dst_access_mask = .{},
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = .{ .depth_bit = true },
                .base_array_layer = 0,
                .layer_count = 1,
                .base_mip_level = 0,
                .level_count = 1,
            },
        },
    };

    command_buffer.pipelineBarrier(
        .{ .all_commands_bit = true },
        .{ .all_commands_bit = true },
        .{},
        0,
        null,
        0,
        null,
        @intCast(image_barriers.len),
        image_barriers.ptr,
    );

    const render_area: vk.Rect2D = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swapchain.size };

    command_buffer.beginRendering(&.{
        .render_area = render_area,
        .layer_count = 1,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = (&vk.RenderingAttachmentInfo{
            .image_view = swapchain_image.image_view,
            .image_layout = .color_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .color = .{ .float_32 = .{ 0.0, 0.1, 0.1, 0.0 } } },
        })[0..1],
        .p_depth_attachment = &.{
            .image_view = depth_image.view_handle,
            .image_layout = .depth_attachment_optimal,
            .resolve_mode = .{},
            .resolve_image_layout = .undefined,
            .load_op = .clear,
            .store_op = .dont_care,
            .clear_value = .{ .depth_stencil = .{ .depth = 1.0, .stencil = 0 } },
        },
        .p_stencil_attachment = null,
    });

    if (build_fn_opt) |build_fn| {
        build_fn(build_data, self.device.device, command_buffer, self.bindless_layout, render_area.extent);
    }

    command_buffer.endRendering();

    command_buffer.pipelineBarrier(
        .{ .all_commands_bit = true },
        .{ .all_commands_bit = true },
        .{},
        0,
        null,
        0,
        null,
        1,
        @ptrCast(&vk.ImageMemoryBarrier{
            .image = swapchain_image.image,
            .old_layout = .color_attachment_optimal,
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
        }),
    );

    try command_buffer.endCommandBuffer();

    const wait_dst_stage_mask: vk.PipelineStageFlags = .{ .all_commands_bit = true };

    const submit_infos: [1]vk.SubmitInfo = .{vk.SubmitInfo{
        .command_buffer_count = @intCast(command_buffers.len),
        .p_command_buffers = &command_buffers,
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&wait_semaphore),
        .p_wait_dst_stage_mask = @ptrCast(&wait_dst_stage_mask),
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast(&present_semaphore),
    }};

    try self.device.device.queueSubmit(self.device.graphics_queue.handle, @intCast(submit_infos.len), &submit_infos, fence);

    const present_result = try self.device.device.queuePresentKHR(self.device.graphics_queue.handle, &.{
        .swapchain_count = 1,
        .p_image_indices = @ptrCast(&swapchain_image.index),
        .p_swapchains = @ptrCast(&swapchain_image.swapchain),
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&present_semaphore),
    });

    if (present_result == .suboptimal_khr) {
        std.log.warn("Swapchain Suboptimal", .{});
        swapchain.out_of_date = true;
    }

    _ = try self.device.device.waitForFences(1, @ptrCast(&fence), 1, std.math.maxInt(u64));
    _ = self.device.device.queueWaitIdle(self.device.graphics_queue.handle) catch {};
}
