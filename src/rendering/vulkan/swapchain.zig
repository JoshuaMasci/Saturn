const std = @import("std");

const vk = @import("vulkan");

const ImageInterface = @import("image.zig").Interface;
const VkDevice = @import("vulkan_device.zig");

const MAX_IMAGE_COUNT: u32 = 8;

pub const Settings = struct {
    image_count: u32,
    format: vk.Format,
    present_mode: vk.PresentModeKHR,
};

pub const SwapchainImage = struct {
    swapchain: vk.SwapchainKHR,
    index: u32,
    image: ImageInterface,
    present_semaphore: vk.Semaphore,
};

const Self = @This();

out_of_date: bool = false,
device: *VkDevice,
surface: vk.SurfaceKHR,
handle: vk.SwapchainKHR,

image_count: usize,
images: [MAX_IMAGE_COUNT]ImageInterface,
image_present_semaphores: [MAX_IMAGE_COUNT]vk.Semaphore,

extent: vk.Extent2D,
format: vk.Format,
color_space: vk.ColorSpaceKHR,
transform: vk.SurfaceTransformFlagsKHR,
composite_alpha: vk.CompositeAlphaFlagsKHR,
present_mode: vk.PresentModeKHR,

pub fn init(
    device: *VkDevice,
    surface: vk.SurfaceKHR,
    window_extent: vk.Extent2D,
    settings: Settings,
    old_swapchain: ?vk.SwapchainKHR,
) !Self {
    const surface_capabilities = try device.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(device.physical_device, surface);

    const image_count = std.math.clamp(settings.image_count, surface_capabilities.min_image_count, @min(surface_capabilities.max_image_count, MAX_IMAGE_COUNT));
    const extent: vk.Extent2D = .{
        .width = std.math.clamp(window_extent.width, surface_capabilities.min_image_extent.width, surface_capabilities.max_image_extent.width),
        .height = std.math.clamp(window_extent.height, surface_capabilities.min_image_extent.height, surface_capabilities.max_image_extent.height),
    };
    const usage = vk.ImageUsageFlags{
        .transfer_src_bit = false,
        .transfer_dst_bit = false,
        .sampled_bit = true,
        .color_attachment_bit = true,
    };

    const color_space = .srgb_nonlinear_khr;
    const transform = surface_capabilities.current_transform;
    const composite_alpha: vk.CompositeAlphaFlagsKHR = .{ .opaque_bit_khr = true };

    //const present_mode = getFirstSupportedPresentMode(device, surface, &.{.mailbox_khr}) orelse .fifo_khr;

    const handle = try device.proxy.createSwapchainKHR(&.{
        .flags = .{},
        .surface = surface,
        .min_image_count = image_count,
        .image_format = settings.format,
        .image_color_space = color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = usage,
        .image_sharing_mode = .exclusive,
        .pre_transform = transform,
        .composite_alpha = composite_alpha,
        .present_mode = settings.present_mode,
        .clipped = 0,
        .old_swapchain = old_swapchain orelse .null_handle,
    }, null);

    var actual_image_count: u32 = 0;
    _ = try device.proxy.getSwapchainImagesKHR(handle, &actual_image_count, null);

    if (actual_image_count > MAX_IMAGE_COUNT) {
        return error.TooManyImages;
    }

    var image_handles: [MAX_IMAGE_COUNT]vk.Image = undefined;
    _ = try device.proxy.getSwapchainImagesKHR(handle, &actual_image_count, &image_handles);

    var images: [MAX_IMAGE_COUNT]ImageInterface = undefined;
    var image_present_semaphores: [MAX_IMAGE_COUNT]vk.Semaphore = undefined;

    for (image_handles[0..actual_image_count], images[0..actual_image_count], image_present_semaphores[0..actual_image_count]) |image_handle, *swapchain_image, *semaphore| {
        const view_handle = try device.proxy.createImageView(&.{
            .view_type = .@"2d",
            .image = image_handle,
            .format = settings.format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        swapchain_image.* = .{
            .layout = .undefined,
            .extent = extent,
            .format = settings.format,
            .usage = usage,
            .handle = image_handle,
            .view_handle = view_handle,
            .sampled_binding = null, //TODO: bind swapchain if requested
        };
        semaphore.* = try device.proxy.createSemaphore(&.{}, null);
    }

    return .{
        .device = device,
        .surface = surface,
        .handle = handle,
        .image_count = actual_image_count,
        .images = images,
        .image_present_semaphores = image_present_semaphores,
        .extent = extent,
        .format = settings.format,
        .color_space = color_space,
        .transform = transform,
        .composite_alpha = composite_alpha,
        .present_mode = settings.present_mode,
    };
}

pub fn deinit(self: Self) void {
    for (self.images[0..self.image_count], self.image_present_semaphores[0..self.image_count]) |image, semaphore| {
        self.device.proxy.destroyImageView(image.view_handle, null);
        self.device.proxy.destroySemaphore(semaphore, null);
    }

    self.device.proxy.destroySwapchainKHR(self.handle, null);
}

pub fn getSettings(self: Self) Settings {
    return .{
        .image_count = @intCast(self.image_count),
        .format = self.format,
        .present_mode = self.present_mode,
    };
}

pub fn acquireNextImage(
    self: *Self,
    timeout: ?u64,
    wait_semaphore: vk.Semaphore,
    wait_fence: vk.Fence,
) vk.DeviceProxy.AcquireNextImageKHRError!SwapchainImage {
    const result = try self.device.proxy.acquireNextImageKHR(
        self.handle,
        timeout orelse std.math.maxInt(u64),
        wait_semaphore,
        wait_fence,
    );

    if (result.result == .suboptimal_khr) {
        std.log.warn("acquireNextImageKHR Swapchain Suboptimal", .{});
        self.out_of_date = true;
    }

    return .{
        .swapchain = self.handle,
        .index = result.image_index,
        .image = self.images[result.image_index],
        .present_semaphore = self.image_present_semaphores[result.image_index],
    };
}

pub fn queuePresent(
    self: *Self,
    queue: vk.Queue,
    index: u32,
    present_semaphore: vk.Semaphore,
) vk.DeviceProxy.QueuePresentKHRError!void {
    const present_result = try self.device.proxy.queuePresentKHR(queue, &.{
        .swapchain_count = 1,
        .p_image_indices = @ptrCast(&index),
        .p_swapchains = @ptrCast(&self.handle),
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&present_semaphore),
    });

    if (present_result == .suboptimal_khr) {
        std.log.warn("queuePresentKHR Swapchain Suboptimal", .{});
        self.out_of_date = true;
    }
}

fn getFirstSupportedPresentMode(device: *VkDevice, surface: vk.SurfaceKHR, desired_present_modes: []const vk.PresentModeKHR) ?vk.PresentModeKHR {
    var supported_present_modes: [8]vk.PresentModeKHR = undefined;
    var supported_present_mode_count: u32 = 0;

    _ = device.instance.getPhysicalDeviceSurfacePresentModesKHR(device.physical_device, surface, &supported_present_mode_count, null) catch |err| {
        std.log.err("vkGetPhysicalDeviceSurfacePresentModesKHR Failed: {}", .{err});
        return null;
    };
    supported_present_mode_count = @max(supported_present_mode_count, @as(u32, @intCast(supported_present_modes.len)));
    _ = device.instance.getPhysicalDeviceSurfacePresentModesKHR(device.physical_device, surface, &supported_present_mode_count, &supported_present_modes) catch |err| {
        std.log.err("vkGetPhysicalDeviceSurfacePresentModesKHR Failed: {}", .{err});
        return null;
    };

    for (desired_present_modes) |desired_mode| {
        for (supported_present_modes[0..supported_present_mode_count]) |supported_mode| {
            if (desired_mode == supported_mode) {
                return desired_mode;
            }
        }
    }

    return null;
}
