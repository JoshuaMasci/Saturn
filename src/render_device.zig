const std = @import("std");
const vk = @import("vulkan");
const Device = @import("vulkan/device.zig").Device;
const IdPool = @import("id_pool.zig").IdPool;

//TODO Generate based on device support
const ALL_STAGES = vk.ShaderStageFlags{
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
};

//Bindless descriptor
const DescriptorSet = struct {
    const Self = @This();
    device: *Device,
    layout: vk.DescriptorSetLayout,
    pool: vk.DescriptorPool,
    set: vk.DescriptorSet,
    storage_buffer_indices: IdPool,

    fn init(device: *Device, allocator: std.mem.Allocator, binding_counts: BindingCount) !Self {
        var bindings = &[_]vk.DescriptorSetLayoutBinding{.{
            .binding = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = binding_counts.storage_buffer,
            .stage_flags = ALL_STAGES,
            .p_immutable_samplers = null,
        }};
        var pool_sizes = &[_]vk.DescriptorPoolSize{.{
            .type = .storage_buffer,
            .descriptor_count = binding_counts.storage_buffer,
        }};

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

        return Self{
            .device = device,
            .layout = layout,
            .pool = pool,
            .set = set,
            .storage_buffer_indices = IdPool.init(allocator, 0, binding_counts.storage_buffer),
        };
    }

    fn deinit(self: *Self) void {
        self.storage_buffer_indices.deinit();
        self.device.base.destroyDescriptorPool(self.device.handle, self.pool, null);
        self.device.base.destroyDescriptorSetLayout(self.device.handle, self.layout, null);
    }
};

//Manages creation and descruction of all buffers and images
const Resources = struct {};

//Manages creation and descruction of all pipelines (except ray-tracing)
const PipelineCache = struct {};

pub const RenderDevice = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    device: *Device,
    descriptor_set: DescriptorSet,
    resources: Resources,
    pipeline_layout: vk.PipelineLayout,
    pipeline_cache: PipelineCache,

    pub fn init(allocator: std.mem.Allocator, device: *Device) !Self {
        var descriptor_set = try DescriptorSet.init(device, allocator, .{ .storage_buffer = 4096 });

        var descriptor_set_layouts = &[_]vk.DescriptorSetLayout{descriptor_set.layout};
        var push_constant_ranges = &[_]vk.PushConstantRange{.{
            .stage_flags = ALL_STAGES,
            .offset = 0,
            .size = 128,
        }};
        var pipeline_layout = try device.base.createPipelineLayout(device.handle, &.{
            .flags = .{},
            .set_layout_count = @intCast(u32, descriptor_set_layouts.len),
            .p_set_layouts = descriptor_set_layouts,
            .push_constant_range_count = @intCast(u32, push_constant_ranges.len),
            .p_push_constant_ranges = push_constant_ranges,
        }, null);

        return Self{
            .allocator = allocator,
            .device = device,
            .descriptor_set = descriptor_set,
            .pipeline_layout = pipeline_layout,
            .pipeline_cache = .{},
            .resources = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.base.destroyPipelineLayout(self.device.handle, self.pipeline_layout, null);
        self.descriptor_set.deinit();
    }
};
