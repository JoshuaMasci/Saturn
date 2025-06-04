const std = @import("std");

const vk = @import("vulkan");

const VkDevice = @import("vulkan_device.zig");
const GpuAllocator = @import("gpu_allocator.zig");

const Self = @This();

device: *VkDevice,
handle: vk.Sampler,

pub fn init(device: *VkDevice, filter_mode: vk.Filter, address_mode: vk.SamplerAddressMode) !Self {
    const handle = try device.device.createSampler(&.{
        .min_filter = filter_mode,
        .mag_filter = filter_mode,
        .mipmap_mode = .nearest,
        .address_mode_u = address_mode,
        .address_mode_v = address_mode,
        .address_mode_w = address_mode,
        .mip_lod_bias = 0.0,
        .anisotropy_enable = 0,
        .max_anisotropy = 0.0,
        .compare_enable = 0,
        .compare_op = .always,
        .min_lod = 0.0,
        .max_lod = vk.LOD_CLAMP_NONE,
        .border_color = .float_opaque_black,
        .unnormalized_coordinates = 0,
    }, null);
    errdefer device.device.destroySampler(handle, null);

    return .{
        .device = device,
        .handle = handle,
    };
}

pub fn deinit(self: Self) void {
    self.device.device.destroySampler(self.handle, null);
}
