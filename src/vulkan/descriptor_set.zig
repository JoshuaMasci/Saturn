const std = @import("std");
const vk = @import("vulkan");

const Device = @import("device.zig");
const IdPool = @import("../id_pool.zig");

const Buffer = @import("buffer.zig");
const Image = @import("image.zig");

pub const BindingType = enum {
    storage_buffer,
    storage_image,
    sampled_image,
    sampler,
};

pub const Binding = struct {
    binding_type: BindingType,
    index: u32,
    set: *Self, //Pointer to set
    pub fn deinit(self: *@This()) void {
        self.set.freeBinding(self.binding_type, self.index);
    }
};

//TODO Generate based on device support
pub const ALL_STAGES = vk.ShaderStageFlags{
    .vertex_bit = true,
    .tessellation_control_bit = true,
    .tessellation_evaluation_bit = true,
    .geometry_bit = true,
    .fragment_bit = true,
    .compute_bit = true,
    .task_bit_nv = true,
    .mesh_bit_nv = true,
    .raygen_bit_khr = true,
    .any_hit_bit_khr = true,
    .closest_hit_bit_khr = true,
    .miss_bit_khr = true,
    .intersection_bit_khr = true,
    .callable_bit_khr = true,
};

const BindingCount = struct {
    storage_buffer: u32,
    storage_image: u32,
    sampled_image: u32,
    sampler: u32,
};

const Self = @This();
allocator: std.mem.Allocator,
binding_counts: BindingCount,
device: *Device,
empty_buffer: Buffer,
empty_image: Image,
empty_sampler: vk.Sampler,
layout: vk.DescriptorSetLayout,
pool: vk.DescriptorPool,
set: vk.DescriptorSet,
storage_buffer_indices: IdPool,

pub fn init(allocator: std.mem.Allocator, device: *Device, empty_buffer: Buffer, empty_image: Image, empty_sampler: vk.Sampler, binding_counts: BindingCount) !Self {
    var bindings = &[_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = binding_counts.storage_buffer,
            .stage_flags = ALL_STAGES,
            .p_immutable_samplers = null,
        },
        .{
            .binding = 1,
            .descriptor_type = .storage_image,
            .descriptor_count = binding_counts.storage_image,
            .stage_flags = ALL_STAGES,
            .p_immutable_samplers = null,
        },
        .{
            .binding = 2,
            .descriptor_type = .sampled_image,
            .descriptor_count = binding_counts.sampled_image,
            .stage_flags = ALL_STAGES,
            .p_immutable_samplers = null,
        },
        .{
            .binding = 3,
            .descriptor_type = .sampler,
            .descriptor_count = binding_counts.sampler,
            .stage_flags = ALL_STAGES,
            .p_immutable_samplers = null,
        },
    };
    var pool_sizes = &[_]vk.DescriptorPoolSize{
        .{
            .type = .storage_buffer,
            .descriptor_count = binding_counts.storage_buffer,
        },
        .{
            .type = .storage_image,
            .descriptor_count = binding_counts.storage_image,
        },
        .{
            .type = .sampled_image,
            .descriptor_count = binding_counts.sampled_image,
        },
        .{
            .type = .sampler,
            .descriptor_count = binding_counts.sampler,
        },
    };

    var layout = try device.base.createDescriptorSetLayout(device.handle, &.{
        .flags = .{},
        .binding_count = @intCast(u32, bindings.len),
        .p_bindings = bindings,
    }, null);

    var pool = try device.base.createDescriptorPool(device.handle, &.{
        .flags = .{},
        .max_sets = 1,
        .pool_size_count = @intCast(u32, pool_sizes.len),
        .p_pool_sizes = pool_sizes,
    }, null);

    var set = vk.DescriptorSet.null_handle;
    try device.base.allocateDescriptorSets(device.handle, &.{
        .descriptor_pool = pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &layout),
    }, @ptrCast([*]vk.DescriptorSet, &set));

    var self = Self{
        .allocator = allocator,
        .binding_counts = binding_counts,
        .device = device,
        .empty_buffer = empty_buffer,
        .empty_image = empty_image,
        .empty_sampler = empty_sampler,
        .layout = layout,
        .pool = pool,
        .set = set,
        .storage_buffer_indices = IdPool.init(allocator, 0, binding_counts.storage_buffer),
    };

    try self.writeNullBuffers(0, binding_counts.storage_buffer, .storage_buffer);
    try self.writeNullImages(1, binding_counts.storage_image, .storage_image, .general);
    try self.writeNullImages(2, binding_counts.sampled_image, .sampled_image, .shader_read_only_optimal);
    try self.writeNullSamplers(3, binding_counts.sampler);

    return self;
}

pub fn deinit(self: *Self) void {
    self.storage_buffer_indices.deinit();
    self.device.base.destroyDescriptorPool(self.device.handle, self.pool, null);
    self.device.base.destroyDescriptorSetLayout(self.device.handle, self.layout, null);
    self.device.base.destroySampler(self.device.handle, self.empty_sampler, null);
    self.empty_image.deinit();
    self.empty_buffer.deinit();
}

fn writeNullBuffers(self: *Self, binding: u32, count: u32, descriptor_type: vk.DescriptorType) !void {
    var descriptor_writes: []vk.WriteDescriptorSet = try self.allocator.alloc(vk.WriteDescriptorSet, count);
    defer self.allocator.free(descriptor_writes);

    var null_buffer_info = vk.DescriptorBufferInfo{
        .buffer = self.empty_buffer.handle,
        .offset = 0,
        .range = vk.WHOLE_SIZE,
    };
    var null_buffer_info_ptr: [*]vk.DescriptorBufferInfo = @ptrCast([*]vk.DescriptorBufferInfo, &null_buffer_info);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        descriptor_writes[i] = .{
            .dst_set = self.set,
            .dst_binding = binding,
            .dst_array_element = i,
            .descriptor_count = 1,
            .descriptor_type = descriptor_type,
            .p_image_info = undefined,
            .p_buffer_info = null_buffer_info_ptr,
            .p_texel_buffer_view = undefined,
        };
    }

    self.device.base.updateDescriptorSets(self.device.handle, count, @ptrCast([*]vk.WriteDescriptorSet, descriptor_writes), 0, undefined);
}

fn writeNullImages(self: *Self, binding: u32, count: u32, descriptor_type: vk.DescriptorType, layout: vk.ImageLayout) !void {
    var descriptor_writes: []vk.WriteDescriptorSet = try self.allocator.alloc(vk.WriteDescriptorSet, count);
    defer self.allocator.free(descriptor_writes);

    var null_image_info = vk.DescriptorImageInfo{
        .sampler = .null_handle,
        .image_view = self.empty_image.view,
        .image_layout = layout,
    };
    var null_image_info_ptr: [*]vk.DescriptorImageInfo = @ptrCast([*]vk.DescriptorImageInfo, &null_image_info);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        descriptor_writes[i] = .{
            .dst_set = self.set,
            .dst_binding = binding,
            .dst_array_element = i,
            .descriptor_count = 1,
            .descriptor_type = descriptor_type,
            .p_image_info = null_image_info_ptr,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        };
    }

    self.device.base.updateDescriptorSets(self.device.handle, count, @ptrCast([*]vk.WriteDescriptorSet, descriptor_writes), 0, undefined);
}

fn writeNullSamplers(self: *Self, binding: u32, count: u32) !void {
    var descriptor_writes: []vk.WriteDescriptorSet = try self.allocator.alloc(vk.WriteDescriptorSet, count);
    defer self.allocator.free(descriptor_writes);

    var null_sampler_info = vk.DescriptorImageInfo{
        .sampler = self.empty_sampler,
        .image_view = .null_handle,
        .image_layout = .@"undefined",
    };
    var null_sampler_info_ptr: [*]vk.DescriptorImageInfo = @ptrCast([*]vk.DescriptorImageInfo, &null_sampler_info);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        descriptor_writes[i] = .{
            .dst_set = self.set,
            .dst_binding = binding,
            .dst_array_element = i,
            .descriptor_count = 1,
            .descriptor_type = .sampler,
            .p_image_info = null_sampler_info_ptr,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        };
    }

    self.device.base.updateDescriptorSets(self.device.handle, count, @ptrCast([*]vk.WriteDescriptorSet, descriptor_writes), 0, undefined);
}
