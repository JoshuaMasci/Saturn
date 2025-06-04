const std = @import("std");

const vk = @import("vulkan");

const VkDevice = @import("vulkan_device.zig");
const ImageInterface = @import("image.zig").Interface;

const MAX_IMAGE_COUNT: u32 = 8;

pub const SwapchainImage = struct {
    swapchain: vk.SwapchainKHR,
    index: u32,
    image: ImageInterface,
};

const Self = @This();

out_of_date: bool = false,
device: *VkDevice,
surface: vk.SurfaceKHR,
handle: vk.SwapchainKHR,

image_count: usize,
images: [MAX_IMAGE_COUNT]ImageInterface,

extent: vk.Extent2D,
format: vk.Format,
color_space: vk.ColorSpaceKHR,
transform: vk.SurfaceTransformFlagsKHR,
composite_alpha: vk.CompositeAlphaFlagsKHR,
present_mode: vk.PresentModeKHR,

pub fn init(device: *VkDevice, surface: vk.SurfaceKHR, window_extent: vk.Extent2D, old_swapchain: ?vk.SwapchainKHR) !Self {
    const surface_capabilities = try device.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(device.physical_device, surface);

    //TODO: take all of this in from settings
    const image_count = std.math.clamp(3, surface_capabilities.min_image_count, @max(surface_capabilities.max_image_count, MAX_IMAGE_COUNT));
    const extent: vk.Extent2D = .{
        .width = std.math.clamp(window_extent.width, surface_capabilities.min_image_extent.width, surface_capabilities.max_image_extent.width),
        .height = std.math.clamp(window_extent.height, surface_capabilities.min_image_extent.height, surface_capabilities.max_image_extent.height),
    };
    const format = .b8g8r8a8_unorm;
    const usage = vk.ImageUsageFlags{
        .transfer_src_bit = false,
        .transfer_dst_bit = false,
        .sampled_bit = true,
        .color_attachment_bit = true,
    };

    const color_space = .srgb_nonlinear_khr;
    const transform = surface_capabilities.current_transform;
    const composite_alpha: vk.CompositeAlphaFlagsKHR = .{ .opaque_bit_khr = true };
    const present_mode = .fifo_khr;

    const handle = try device.device.createSwapchainKHR(&.{
        .flags = .{},
        .surface = surface,
        .min_image_count = image_count,
        .image_format = format,
        .image_color_space = color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = usage,
        .image_sharing_mode = .exclusive,
        .pre_transform = transform,
        .composite_alpha = composite_alpha,
        .present_mode = present_mode,
        .clipped = 0,
        .old_swapchain = old_swapchain orelse .null_handle,
    }, null);

    var actual_image_count: u32 = 0;
    _ = try device.device.getSwapchainImagesKHR(handle, &actual_image_count, null);

    if (actual_image_count > MAX_IMAGE_COUNT) {
        return error.TooManyImages;
    }

    var image_handles: [MAX_IMAGE_COUNT]vk.Image = undefined;
    _ = try device.device.getSwapchainImagesKHR(handle, &actual_image_count, &image_handles);

    var images: [MAX_IMAGE_COUNT]ImageInterface = undefined;
    for (image_handles[0..actual_image_count], images[0..actual_image_count]) |image_handle, *swapchain_image| {
        const view_handle = try device.device.createImageView(&.{
            .view_type = .@"2d",
            .image = image_handle,
            .format = format,
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
            .format = format,
            .usage = usage,
            .handle = image_handle,
            .view_handle = view_handle,
            .sampled_binding = null, //TODO: bind swapchain if requested
        };
    }

    return .{
        .device = device,
        .surface = surface,
        .handle = handle,
        .image_count = actual_image_count,
        .images = images,
        .extent = extent,
        .format = format,
        .color_space = color_space,
        .transform = transform,
        .composite_alpha = composite_alpha,
        .present_mode = present_mode,
    };
}

pub fn deinit(self: Self) void {
    for (self.images[0..self.image_count]) |image| {
        self.device.device.destroyImageView(image.view_handle, null);
    }

    self.device.device.destroySwapchainKHR(self.handle, null);
}

pub fn acquireNextImage(
    self: *Self,
    timeout: ?u64,
    wait_semaphore: vk.Semaphore,
    wait_fence: vk.Fence,
) !SwapchainImage {
    const result = try self.device.device.acquireNextImageKHR(
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
    };
}

pub fn queuePresent(
    self: *Self,
    queue: vk.Queue,
    index: u32,
    present_semaphore: vk.Semaphore,
) !void {
    const present_result = try self.device.device.queuePresentKHR(queue, &.{
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
