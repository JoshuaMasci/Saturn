const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vulkan");
usingnamespace @import("instance.zig");
usingnamespace @import("device.zig");

pub const SwapchainInfo = struct {
    image_count: u32,
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    usage: vk.ImageUsageFlags,
    mode: vk.PresentModeKHR,
};

pub const Swapchain = struct {
    const Self = @This();

    allocator: *Allocator,
    instance_dispatch: InstanceDispatch,
    device: Device,
    pdevice: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,

    invalid: bool,
    extent: vk.Extent2D,
    handle: vk.SwapchainKHR,
    images: std.ArrayList(vk.Image),
    image_views: std.ArrayList(vk.ImageView),
    render_pass: vk.RenderPass,
    framebuffers: std.ArrayList(vk.Framebuffer),

    pub fn init(allocator: *Allocator, instance_dispatch: InstanceDispatch, device: Device, pdevice: vk.PhysicalDevice, surface: vk.SurfaceKHR) !Self {
        var self = Self{
            .allocator = allocator,
            .instance_dispatch = instance_dispatch,
            .device = device,
            .pdevice = pdevice,
            .surface = surface,
            .invalid = false,
            .extent = vk.Extent2D{ .width = 0, .height = 0 },
            .handle = .null_handle,
            .images = std.ArrayList(vk.Image).init(allocator),
            .image_views = std.ArrayList(vk.ImageView).init(allocator),
            .render_pass = .null_handle,
            .framebuffers = std.ArrayList(vk.Framebuffer).init(allocator),
        };
        try self.rebuild();
        return self;
    }

    pub fn deinit(self: Self) void {
        //Wait for all frames to finish before deinitializing swapchain
        self.device.dispatch.deviceWaitIdle(self.device.handle) catch {};

        self.device.dispatch.destroySwapchainKHR(self.device.handle, self.handle, null);
        self.images.deinit();

        for (self.image_views.items) |view| {
            self.device.dispatch.destroyImageView(self.device.handle, view, null);
        }
        self.image_views.deinit();

        for (self.framebuffers.items) |framebuffer| {
            self.device.dispatch.destroyFramebuffer(self.device.handle, framebuffer, null);
        }
        self.framebuffers.deinit();

        self.device.dispatch.destroyRenderPass(self.device.handle, self.render_pass, null);
    }

    pub fn getNextImage(self: *Self, image_ready: vk.Semaphore) ?u32 {
        //Try rebuilding once a frame when invalid
        if (self.invalid) {
            self.rebuild() catch |err| panic("Swapchain Rebuild Failed: {}", .{err});

            if (self.invalid) {
                return null;
            }
        }

        var image_index: u32 = undefined;
        const result_error = self.device.dispatch.acquireNextImageKHR(
            self.device.handle,
            self.handle,
            std.math.maxInt(u64),
            image_ready,
            .null_handle,
        );

        if (result_error) |result| {
            return result.image_index;
        } else |err| switch (err) {
            error.OutOfDateKHR => {
                self.invalid = true;
                return null;
            },
            else => panic("Swapchain Next Image Failed: {}", .{err}),
        }
    }

    pub fn rebuild(self: *Self) !void {
        const caps = try self.instance_dispatch.getPhysicalDeviceSurfaceCapabilitiesKHR(self.pdevice, self.surface);

        //Invalid if the either extent is 0
        if (caps.current_extent.width == 0 or caps.current_extent.height == 0) {
            self.invalid = true;
            return;
        }

        //Hardcoded Temp, TODO fix
        const queue_family_index = [_]u32{0};
        const image_useage = vk.ImageUsageFlags{ .color_attachment_bit = true, .transfer_dst_bit = true };

        const image_count = std.math.min(caps.min_image_count + 1, caps.max_image_count);
        const image_extent = getImageExtent(caps.current_extent, caps.min_image_extent, caps.max_image_extent);
        const surface_format = try getSurfaceFormat(self.allocator, self.instance_dispatch, self.pdevice, self.surface);
        const present_mode = try getPresentMode(self.allocator, self.instance_dispatch, self.pdevice, self.surface);

        var create_info = vk.SwapchainCreateInfoKHR{
            .surface = self.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = image_extent,
            .image_array_layers = 1,
            .image_usage = image_useage,
            .image_sharing_mode = .exclusive,
            .queue_family_index_count = queue_family_index.len,
            .p_queue_family_indices = &queue_family_index,
            .pre_transform = caps.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = self.handle,
            .flags = .{},
        };
        var swapchain = try self.device.dispatch.createSwapchainKHR(self.device.handle, create_info, null);

        var count: u32 = undefined;
        _ = try self.device.dispatch.getSwapchainImagesKHR(self.device.handle, swapchain, &count, null);
        var images = try std.ArrayList(vk.Image).initCapacity(self.allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try images.append(.null_handle);
        }
        _ = try self.device.dispatch.getSwapchainImagesKHR(self.device.handle, swapchain, &count, @ptrCast([*]vk.Image, images.items));

        var image_views = try createImageViews(self.allocator, self.device, surface_format.format, &images);
        var render_pass = try createRenderPass(self.device, surface_format.format);
        var framebuffers = try createFramebuffers(self.allocator, self.device, render_pass, surface_format.format, image_extent, &image_views);

        //Destroy old
        self.deinit();

        //Update Object
        self.invalid = false;
        self.extent = image_extent;
        self.handle = swapchain;
        self.images = images;
        self.image_views = image_views;
        self.render_pass = render_pass;
        self.framebuffers = framebuffers;
    }

    fn getSurfaceFormat(allocator: *Allocator, instance_dispatch: InstanceDispatch, pdevice: vk.PhysicalDevice, surface: vk.SurfaceKHR) !vk.SurfaceFormatKHR {
        const preferred = vk.SurfaceFormatKHR{
            .format = .b8g8r8a8_unorm,
            .color_space = .srgb_nonlinear_khr,
        };

        var count: u32 = undefined;
        _ = try instance_dispatch.getPhysicalDeviceSurfaceFormatsKHR(pdevice, surface, &count, null);

        const surface_formats = try allocator.alloc(vk.SurfaceFormatKHR, count);
        defer allocator.free(surface_formats);

        _ = try instance_dispatch.getPhysicalDeviceSurfaceFormatsKHR(pdevice, surface, &count, surface_formats.ptr);

        for (surface_formats) |surface_format| {
            if (preferred.format == surface_format.format and preferred.color_space == surface_format.color_space) {
                return preferred;
            }
        }

        // There must always be at least one supported surface format
        return surface_formats[0];
    }

    fn getPresentMode(allocator: *Allocator, instance_dispatch: InstanceDispatch, pdevice: vk.PhysicalDevice, surface: vk.SurfaceKHR) !vk.PresentModeKHR {
        var count: u32 = undefined;
        _ = try instance_dispatch.getPhysicalDeviceSurfacePresentModesKHR(pdevice, surface, &count, null);

        const present_modes = try allocator.alloc(vk.PresentModeKHR, count);
        defer allocator.free(present_modes);

        _ = try instance_dispatch.getPhysicalDeviceSurfacePresentModesKHR(pdevice, surface, &count, present_modes.ptr);

        const preferred = [_]vk.PresentModeKHR{
            .mailbox_khr,
            .fifo_khr,
            .immediate_khr,
        };

        for (preferred) |mode| {
            if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, mode) != null) {
                return mode;
            }
        }

        return .fifo_khr;
    }

    fn getImageExtent(current: vk.Extent2D, min: vk.Extent2D, max: vk.Extent2D) vk.Extent2D {
        return vk.Extent2D{
            .width = std.math.clamp(current.width, min.width, max.width),
            .height = std.math.clamp(current.height, min.height, max.height),
        };
    }

    fn createImageViews(allocator: *Allocator, device: Device, format: vk.Format, images: *std.ArrayList(vk.Image)) !std.ArrayList(vk.ImageView) {
        var image_views = try std.ArrayList(vk.ImageView).initCapacity(allocator, images.items.len);
        for (images.items) |image| {
            try image_views.append(try device.dispatch.createImageView(device.handle, .{
                .flags = .{},
                .image = image,
                .view_type = .@"2d",
                .format = format,
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            }, null));
        }
        return image_views;
    }

    fn createRenderPass(device: Device, format: vk.Format) !vk.RenderPass {
        const color_attachment = vk.AttachmentDescription{
            .flags = .{},
            .format = format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .@"undefined",
            .final_layout = .present_src_khr,
        };

        const color_attachment_ref = vk.AttachmentReference{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        };

        const subpass = vk.SubpassDescription{
            .flags = .{},
            .pipeline_bind_point = .graphics,
            .input_attachment_count = 0,
            .p_input_attachments = undefined,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast([*]const vk.AttachmentReference, &color_attachment_ref),
            .p_resolve_attachments = null,
            .p_depth_stencil_attachment = null,
            .preserve_attachment_count = 0,
            .p_preserve_attachments = undefined,
        };

        return try device.dispatch.createRenderPass(device.handle, .{
            .flags = .{},
            .attachment_count = 1,
            .p_attachments = @ptrCast([*]const vk.AttachmentDescription, &color_attachment),
            .subpass_count = 1,
            .p_subpasses = @ptrCast([*]const vk.SubpassDescription, &subpass),
            .dependency_count = 0,
            .p_dependencies = undefined,
        }, null);
    }

    fn createFramebuffers(allocator: *Allocator, device: Device, render_pass: vk.RenderPass, format: vk.Format, extent: vk.Extent2D, image_views: *std.ArrayList(vk.ImageView)) !std.ArrayList(vk.Framebuffer) {
        var framebuffers = try std.ArrayList(vk.Framebuffer).initCapacity(allocator, image_views.items.len);
        for (image_views.items) |image_view| {
            try framebuffers.append(try device.dispatch.createFramebuffer(device.handle, .{
                .flags = .{},
                .render_pass = render_pass,
                .attachment_count = 1,
                .p_attachments = @ptrCast([*]const vk.ImageView, &image_view),
                .width = extent.width,
                .height = extent.height,
                .layers = 1,
            }, null));
        }
        return framebuffers;
    }
};
