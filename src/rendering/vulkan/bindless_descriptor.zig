const std = @import("std");

const vk = @import("vulkan");

const Buffer = @import("buffer.zig");
const VkDevice = @import("vulkan_device.zig");
const Image = @import("image.zig");
const Sampler = @import("sampler.zig");

pub const DescriptorCounts = struct {
    uniform_buffers: u32,
    storage_buffers: u32,
    sampled_images: u32,
    storage_images: u32,
    accleration_structures: u32 = 0,
};

// fn Binding(comptime BindingType: u16) type {
//     return struct {
//         index: u16,
//         pub fn toU32(self: @This()) u32 {
//             const u32_index: u32 = @intCast(self.index);
//             return BindingType | (u32_index >> 16);
//         }
//     };
// }

// pub const UniformBufferBinding = Binding(1);
// pub const StorageBufferBinding = Binding(2);
// pub const SampledImageBinding = Binding(3);
// pub const StorageImageBinding = Binding(4);

const Self = @This();

device: *VkDevice,
layout: vk.DescriptorSetLayout,

pool: vk.DescriptorPool,
set: vk.DescriptorSet,

uniform_buffer_array: BufferDescriptor,
storage_buffer_array: BufferDescriptor,
sampled_image_array: ImageDescriptor,
storage_image_array: ImageDescriptor,

next_sampled_texture_id: u16 = 1,

pub fn init(allocator: std.mem.Allocator, device: *VkDevice, descriptor_counts: DescriptorCounts) !Self {

    //TODO: add flags when RTX-Shaders or Mesh-Shading are enabled
    const All_STAGE_FLAGS = vk.ShaderStageFlags{
        .vertex_bit = true,
        .fragment_bit = true,
        .compute_bit = true,
    };

    const BINDING_COUNT = 5;
    const bindings = [BINDING_COUNT]vk.DescriptorSetLayoutBinding{
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
        .{
            .binding = 4,
            .descriptor_type = .acceleration_structure_khr,
            .descriptor_count = descriptor_counts.accleration_structures,
            .stage_flags = All_STAGE_FLAGS,
        },
    };

    const binding_flags: [BINDING_COUNT]vk.DescriptorBindingFlags = @splat(.{
        .update_after_bind_bit = true,
        .update_unused_while_pending_bit = true,
        .partially_bound_bit = true,
    });

    //TODO: enable 5th binding with raytracing
    const binding_count: u32 = 4;

    const binding_create_info: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
        .binding_count = binding_count,
        .p_binding_flags = &binding_flags,
    };

    const layout = try device.proxy.createDescriptorSetLayout(&.{
        .p_next = @ptrCast(&binding_create_info),
        .binding_count = binding_count,
        .p_bindings = &bindings,
        .flags = .{ .update_after_bind_pool_bit = true },
    }, null);

    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{ .type = .uniform_buffer, .descriptor_count = descriptor_counts.uniform_buffers },
        .{ .type = .storage_buffer, .descriptor_count = descriptor_counts.storage_buffers },
        .{ .type = .combined_image_sampler, .descriptor_count = descriptor_counts.sampled_images },
        .{ .type = .storage_image, .descriptor_count = descriptor_counts.storage_images },
        .{ .type = .acceleration_structure_khr, .descriptor_count = descriptor_counts.accleration_structures },
    };

    const pool = try device.proxy.createDescriptorPool(&.{ .max_sets = 1, .pool_size_count = binding_count, .p_pool_sizes = &pool_sizes, .flags = .{ .update_after_bind_bit = true } }, null);

    var set: vk.DescriptorSet = .null_handle;
    try device.proxy.allocateDescriptorSets(&.{ .descriptor_pool = pool, .descriptor_set_count = 1, .p_set_layouts = @ptrCast(&layout) }, @ptrCast(&set));

    return Self{
        .device = device,
        .layout = layout,
        .pool = pool,
        .set = set,
        .uniform_buffer_array = .init(allocator, device, set, 0, .uniform_buffer, descriptor_counts.uniform_buffers),
        .storage_buffer_array = .init(allocator, device, set, 1, .storage_buffer, descriptor_counts.storage_buffers),
        .sampled_image_array = .init(allocator, device, set, 2, .combined_image_sampler, .shader_read_only_optimal, descriptor_counts.sampled_images),
        .storage_image_array = .init(allocator, device, set, 3, .storage_image, .general, descriptor_counts.storage_images),
    };
}

pub fn deinit(self: *Self) void {
    self.device.proxy.destroyDescriptorPool(self.pool, null);
    self.device.proxy.destroyDescriptorSetLayout(self.layout, null);

    self.uniform_buffer_array.deinit();
    self.storage_buffer_array.deinit();
    self.sampled_image_array.deinit();
    self.storage_image_array.deinit();
}

pub fn bind(self: Self, command_buffer: vk.CommandBufferProxy, layout: vk.PipelineLayout) void {
    const bind_points = [_]vk.PipelineBindPoint{ .graphics, .compute };
    for (bind_points) |bind_point| {
        command_buffer.bindDescriptorSets(bind_point, layout, 0, 1, (&self.set)[0..1], 0, null);
    }
}

pub const Binding = struct {
    binding: u32,
    index: u32,
};

const BufferDescriptor = struct {
    device: *VkDevice,
    set: vk.DescriptorSet,

    descriptor_index: u32,
    descriptor_type: vk.DescriptorType,

    index_list: IndexList,

    fn init(
        allocator: std.mem.Allocator,
        device: *VkDevice,
        set: vk.DescriptorSet,
        descriptor_index: u32,
        descriptor_type: vk.DescriptorType,
        array_count: u32,
    ) BufferDescriptor {
        return .{
            .device = device,
            .set = set,
            .descriptor_index = descriptor_index,
            .descriptor_type = descriptor_type,
            .index_list = .init(allocator, 1, array_count),
        };
    }

    fn deinit(self: *BufferDescriptor) void {
        self.index_list.deinit();
    }

    pub fn bind(self: *BufferDescriptor, buffer: Buffer) Binding {
        const index = self.index_list.get().?;

        const buffer_info = vk.DescriptorBufferInfo{
            .buffer = buffer.handle,
            .offset = 0,
            .range = vk.WHOLE_SIZE,
        };
        const descriptor_update = vk.WriteDescriptorSet{
            .descriptor_count = 1,
            .descriptor_type = self.descriptor_type,
            .dst_set = self.set,
            .dst_binding = self.descriptor_index,
            .dst_array_element = @intCast(index),
            .p_buffer_info = @ptrCast(&buffer_info),
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        };
        self.device.proxy.updateDescriptorSets(1, @ptrCast(&descriptor_update), 0, null);

        return .{ .binding = self.descriptor_index, .index = index };
    }

    pub fn clear(self: *BufferDescriptor, binding: Binding) void {
        self.index_list.free(binding.index);

        const buffer_info = vk.DescriptorBufferInfo{
            .buffer = .null_handle,
            .offset = 0,
            .range = vk.WHOLE_SIZE,
        };
        const descriptor_update = vk.WriteDescriptorSet{
            .descriptor_count = 1,
            .descriptor_type = self.descriptor_type,
            .dst_set = self.set,
            .dst_binding = self.descriptor_index,
            .dst_array_element = @intCast(binding.index),
            .p_buffer_info = @ptrCast(&buffer_info),
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        };
        self.device.proxy.updateDescriptorSets(1, @ptrCast(&descriptor_update), 0, null);
    }
};

const ImageDescriptor = struct {
    device: *VkDevice,
    set: vk.DescriptorSet,

    descriptor_index: u32,
    descriptor_type: vk.DescriptorType,
    image_layout: vk.ImageLayout,

    index_list: IndexList,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *VkDevice,
        set: vk.DescriptorSet,
        descriptor_index: u32,
        descriptor_type: vk.DescriptorType,
        image_layout: vk.ImageLayout,
        array_count: u32,
    ) ImageDescriptor {
        return .{
            .device = device,
            .set = set,
            .descriptor_index = descriptor_index,
            .descriptor_type = descriptor_type,
            .image_layout = image_layout,
            .index_list = .init(allocator, 1, array_count),
        };
    }

    pub fn deinit(self: *ImageDescriptor) void {
        self.index_list.deinit();
    }

    pub fn bind(self: *ImageDescriptor, image: Image, sampler: ?Sampler) Binding {
        const index = self.index_list.get().?;

        const image_info = vk.DescriptorImageInfo{
            .sampler = if (sampler) |some| some.handle else .null_handle,
            .image_view = image.view_handle,
            .image_layout = self.image_layout,
        };
        const descriptor_update = vk.WriteDescriptorSet{
            .descriptor_count = 1,
            .descriptor_type = self.descriptor_type,
            .dst_set = self.set,
            .dst_binding = self.descriptor_index,
            .dst_array_element = @intCast(index),
            .p_image_info = @ptrCast(&image_info),
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        };
        self.device.proxy.updateDescriptorSets(1, @ptrCast(&descriptor_update), 0, null);

        return .{ .binding = self.descriptor_index, .index = index };
    }

    pub fn clear(self: *ImageDescriptor, binding: Binding) void {
        self.index_list.free(binding.index);

        const image_info = vk.DescriptorImageInfo{
            .sampler = .null_handle,
            .image_view = .null_handle,
            .image_layout = .undefined,
        };
        const descriptor_update = vk.WriteDescriptorSet{
            .descriptor_count = 1,
            .descriptor_type = self.descriptor_type,
            .dst_set = self.set,
            .dst_binding = self.descriptor_index,
            .dst_array_element = @intCast(binding.index),
            .p_image_info = @ptrCast(&image_info),
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        };
        self.device.proxy.updateDescriptorSets(1, @ptrCast(&descriptor_update), 0, null);
    }
};

const IndexList = struct {
    freed: std.ArrayList(u32),
    next: u32,
    min: u32,
    max: u32,

    pub fn init(allocator: std.mem.Allocator, min: u32, max: u32) IndexList {
        return IndexList{
            .freed = .init(allocator),
            .next = min,
            .min = min,
            .max = max,
        };
    }

    pub fn deinit(self: *IndexList) void {
        self.freed.deinit();
    }

    pub fn get(self: *IndexList) ?u32 {
        if (self.freed.items.len > 0) {
            return self.freed.pop();
        } else if (self.next <= self.max) {
            const idx = self.next;
            self.next += 1;
            return idx;
        } else {
            return null; // exhausted
        }
    }

    pub fn free(self: *IndexList, index: u32) void {
        if (index < self.min or index > self.max) return;
        self.freed.append(index) catch {}; // ignore OOM
    }
};
