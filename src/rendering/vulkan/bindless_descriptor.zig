const std = @import("std");

const vk = @import("vulkan");

const Buffer = @import("buffer.zig");
const Device = @import("device.zig");
const Image = @import("image.zig");
const Sampler = @import("sampler.zig");

pub const DescriptorCounts = struct {
    uniform_buffers: u32,
    storage_buffers: u32,
    sampled_images: u32,
    storage_images: u32,
    //accleration_structures: u32,
};

const Self = @This();

device: *Device,
layout: vk.DescriptorSetLayout,

pool: vk.DescriptorPool,
set: vk.DescriptorSet,

next_sampled_texture_id: u16 = 1,

pub fn init(device: *Device, descriptor_counts: DescriptorCounts) !Self {

    //TODO: add flags when RTX-Shaders or Mesh-Shading are enabled
    const All_STAGE_FLAGS = vk.ShaderStageFlags{
        .vertex_bit = true,
        .fragment_bit = true,
        .compute_bit = true,
    };

    const bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = descriptor_counts.uniform_buffers,
            .stage_flags = All_STAGE_FLAGS,
        },
        .{
            .binding = 1,
            .descriptor_type = .storage_buffer,
            .descriptor_count = descriptor_counts.storage_buffers,
            .stage_flags = All_STAGE_FLAGS,
        },
        .{
            .binding = 2,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = descriptor_counts.sampled_images,
            .stage_flags = All_STAGE_FLAGS,
        },
        .{
            .binding = 3,
            .descriptor_type = .storage_image,
            .descriptor_count = descriptor_counts.storage_images,
            .stage_flags = All_STAGE_FLAGS,
        },
        // .{
        //     .binding = 4,
        //     .descriptor_type = .acceleration_structure_khr,
        //     .descriptor_count = descriptor_counts.accleration_structures,
        //     .stage_flags = All_STAGE_FLAGS,
        // },
    };

    const layout = try device.device.createDescriptorSetLayout(&.{
        .binding_count = bindings.len,
        .p_bindings = &bindings,
    }, null);

    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{ .type = .uniform_buffer, .descriptor_count = descriptor_counts.uniform_buffers },
        .{ .type = .storage_buffer, .descriptor_count = descriptor_counts.storage_buffers },
        .{ .type = .combined_image_sampler, .descriptor_count = descriptor_counts.sampled_images },
        .{ .type = .storage_image, .descriptor_count = descriptor_counts.storage_images },
        //.{ .type = .acceleration_structure_khr, .descriptor_count = descriptor_counts.accleration_structures },
    };

    const pool = try device.device.createDescriptorPool(&.{ .max_sets = 1, .pool_size_count = pool_sizes.len, .p_pool_sizes = &pool_sizes }, null);

    var set: vk.DescriptorSet = .null_handle;
    try device.device.allocateDescriptorSets(&.{ .descriptor_pool = pool, .descriptor_set_count = 1, .p_set_layouts = (&layout)[0..1] }, (&set)[0..1]);

    return Self{
        .device = device,
        .layout = layout,
        .pool = pool,
        .set = set,
    };
}

pub fn deinit(self: Self) void {
    self.device.device.destroyDescriptorPool(self.pool, null);
    self.device.device.destroyDescriptorSetLayout(self.layout, null);
}

pub fn bind(self: Self, command_buffer: vk.CommandBufferProxy, layout: vk.PipelineLayout) void {
    const bind_points = [_]vk.PipelineBindPoint{ .graphics, .compute };
    for (bind_points) |bind_point| {
        command_buffer.bindDescriptorSets(bind_point, layout, 0, 1, (&self.set)[0..1], 0, null);
    }
}

pub fn bindSampledImage(self: *Self, image: Image, sampler: Sampler) u16 {
    const index = self.next_sampled_texture_id;
    self.next_sampled_texture_id += 1;

    const image_info = vk.DescriptorImageInfo{
        .image_layout = .shader_read_only_optimal,
        .image_view = image.view_handle,
        .sampler = sampler.handle,
    };

    const descriptor_update = vk.WriteDescriptorSet{
        .descriptor_count = 1,
        .descriptor_type = .combined_image_sampler,
        .dst_set = self.set,
        .dst_binding = 2,
        .dst_array_element = @intCast(index),
        .p_buffer_info = undefined,
        .p_image_info = (&image_info)[0..1],
        .p_texel_buffer_view = undefined,
    };

    self.device.device.updateDescriptorSets(1, (&descriptor_update)[0..1], 0, null);

    return index;
}
