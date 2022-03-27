const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vulkan");
const Device = @import("device.zig");
const Image = @import("image.zig");

pub const SwapchainInfo = struct {
    image_count: u32,
    format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    usage: vk.ImageUsageFlags,
    mode: vk.PresentModeKHR,
};

pub const SwapchainImageInfo = struct {
    image_index: u32,
    image: Image,
};

pub const Swapchain = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    device: *Device,
    surface: vk.SurfaceKHR,

    invalid: bool,
    handle: vk.SwapchainKHR,

    images: std.ArrayList(Image),

    pub fn init(allocator: std.mem.Allocator, device: *Device, surface: vk.SurfaceKHR) !Self {
        var self = Self{
            .allocator = allocator,
            .device = device,
            .surface = surface,
            .invalid = false,
            .handle = .null_handle,
            .images = std.ArrayList(Image).init(allocator),
        };
        try self.rebuild();
        return self;
    }

    pub fn deinit(self: Self) void {
        //Wait for all frames to finish before deinitializing swapchain
        self.device.base.deviceWaitIdle(self.device.handle) catch {};

        for (self.images.items) |image| {
            image.deinit();
        }
        self.images.deinit();

        self.device.base.destroySwapchainKHR(self.device.handle, self.handle, null);
    }

    pub fn getNextImage(self: *Self, image_ready: vk.Semaphore) ?u32 {
        //Try rebuilding once a frame when invalid
        if (self.invalid) {
            self.rebuild() catch |err| panic("Swapchain Rebuild Failed: {}", .{err});

            if (self.invalid) {
                return null;
            }
        }

        const result_error = self.device.base.acquireNextImageKHR(
            self.device.handle,
            self.handle,
            std.math.maxInt(u64),
            image_ready,
            .null_handle,
        );

        if (result_error) |result| {
            // var image = Image{
            //     .device = null,
            // };

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
        const caps = try self.device.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(self.device.pdevice, self.surface);

        //Invalid if the either extent is 0
        if (caps.current_extent.width == 0 or caps.current_extent.height == 0) {
            self.invalid = true;
            return;
        }

        //Hardcoded Temp, TODO fix
        const queue_family_index = [_]u32{0};

        const image_usage = vk.ImageUsageFlags{ .color_attachment_bit = true, .transfer_dst_bit = true };
        const image_count = std.math.min(caps.min_image_count + 1, caps.max_image_count);
        const image_extent = getImageExtent(caps.current_extent, caps.min_image_extent, caps.max_image_extent);
        const surface_format = try getSurfaceFormat(self.allocator, self.device, self.surface);
        const present_mode = try getPresentMode(self.allocator, self.device, self.surface);

        var create_info = vk.SwapchainCreateInfoKHR{
            .surface = self.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = image_extent,
            .image_array_layers = 1,
            .image_usage = image_usage,
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
        var swapchain = try self.device.base.createSwapchainKHR(self.device.handle, &create_info, null);

        var count: u32 = undefined;
        _ = try self.device.base.getSwapchainImagesKHR(self.device.handle, swapchain, &count, null);
        var swapchain_images = try self.allocator.alloc(vk.Image, count);
        defer self.allocator.free(swapchain_images);
        _ = try self.device.base.getSwapchainImagesKHR(self.device.handle, swapchain, &count, swapchain_images.ptr);

        var swapchain_description = Image.Description{
            .size = .{ image_extent.width, image_extent.height },
            .format = surface_format.format,
            .usage = image_usage,
            .memory_usage = .gpu_only,
        };

        var images = try std.ArrayList(Image).initCapacity(self.allocator, swapchain_images.len);
        for (swapchain_images) |swapchain_image| {
            try images.append(try Image.initSwapchainImage(
                self.device,
                swapchain_image,
                swapchain_description,
            ));
        }

        //Destroy old
        self.deinit();

        //Update Object
        self.invalid = false;
        self.handle = swapchain;
        self.images = images;
    }

    fn getSurfaceFormat(allocator: std.mem.Allocator, device: *Device, surface: vk.SurfaceKHR) !vk.SurfaceFormatKHR {
        const preferred = vk.SurfaceFormatKHR{
            .format = .b8g8r8a8_unorm,
            .color_space = .srgb_nonlinear_khr,
        };

        var count: u32 = undefined;
        _ = try device.instance.getPhysicalDeviceSurfaceFormatsKHR(device.pdevice, surface, &count, null);

        const surface_formats = try allocator.alloc(vk.SurfaceFormatKHR, count);
        defer allocator.free(surface_formats);

        _ = try device.instance.getPhysicalDeviceSurfaceFormatsKHR(device.pdevice, surface, &count, surface_formats.ptr);

        for (surface_formats) |surface_format| {
            if (preferred.format == surface_format.format and preferred.color_space == surface_format.color_space) {
                return preferred;
            }
        }

        // There must always be at least one supported surface format
        return surface_formats[0];
    }

    fn getPresentMode(allocator: std.mem.Allocator, device: *Device, surface: vk.SurfaceKHR) !vk.PresentModeKHR {
        var count: u32 = undefined;
        _ = try device.instance.getPhysicalDeviceSurfacePresentModesKHR(device.pdevice, surface, &count, null);

        const present_modes = try allocator.alloc(vk.PresentModeKHR, count);
        defer allocator.free(present_modes);

        _ = try device.instance.getPhysicalDeviceSurfacePresentModesKHR(device.pdevice, surface, &count, present_modes.ptr);

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
};
