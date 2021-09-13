const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vk.zig");

usingnamespace @import("resource_deleter.zig");
usingnamespace @import("id_pool.zig");
usingnamespace @import("buffer.zig");

const ALL_SHADER_STAGES = vk.ShaderStageFlags{
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

pub const ResourceBindingCounts = struct {
    push_constant_size: u32,
    storage_buffer: u32,
    //storage_image: u32,
    sampled_image: u32,
    sampler: u32,
    //acceleration_structure: u32,
};

pub const DeviceResources = struct {
    const Self = @This();

    allocator: *Allocator,
    pdevice: vk.PhysicalDevice,
    device: vk.Device,
    memory_properties: vk.PhysicalDeviceMemoryProperties,

    descriptor_layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,

    descriptor_pool: vk.DescriptorPool,
    descriptor_set: vk.DescriptorSet,

    //Buffers
    buffers: std.AutoHashMap(u32, Buffer),
    buffer_id_pool: IdPool,

    //Resource Deleters
    current_frame: u32 = 0,
    buffer_deleter: ResourceDeleter(Buffer),

    pub fn init(allocator: *Allocator, pdevice: vk.PhysicalDevice, device: vk.Device, binding_counts: ResourceBindingCounts, frames_in_flight: u32) !Self {
        var memory_properties = vk.vki.getPhysicalDeviceMemoryProperties(pdevice);

        const bindings = [_]vk.DescriptorSetLayoutBinding{.{
            .binding = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = binding_counts.storage_buffer,
            .stage_flags = ALL_SHADER_STAGES,
            .p_immutable_samplers = null,
        }};

        var descriptor_layout = try vk.vkd.createDescriptorSetLayout(
            device,
            .{
                .flags = .{},
                .binding_count = bindings.len,
                .p_bindings = @ptrCast([*]const vk.DescriptorSetLayoutBinding, &bindings[0]),
            },
            null,
        );

        var push_constant_range = vk.PushConstantRange{
            .stage_flags = ALL_SHADER_STAGES,
            .offset = 0,
            .size = binding_counts.push_constant_size,
        };

        var pipeline_layout = try vk.vkd.createPipelineLayout(device, .{
            .flags = .{},
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &descriptor_layout),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, &push_constant_range),
        }, null);

        const pools = [_]vk.DescriptorPoolSize{
            .{
                .type_ = .storage_buffer,
                .descriptor_count = binding_counts.storage_buffer,
            },
        };

        var descriptor_pool = try vk.vkd.createDescriptorPool(device, .{
            .flags = .{},
            .max_sets = 1,
            .pool_size_count = pools.len,
            .p_pool_sizes = @ptrCast([*]const vk.DescriptorPoolSize, &pools[0]),
        }, null);

        var descriptor_set: vk.DescriptorSet = .null_handle;
        _ = try vk.vkd.allocateDescriptorSets(
            device,
            .{
                .descriptor_pool = descriptor_pool,
                .descriptor_set_count = 1,
                .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, &descriptor_layout),
            },
            @ptrCast([*]vk.DescriptorSet, &descriptor_set),
        );

        var buffer_deleter = try ResourceDeleter(Buffer).init(allocator, frames_in_flight);

        return Self{
            .allocator = allocator,
            .pdevice = pdevice,
            .device = device,
            .memory_properties = memory_properties,
            .descriptor_layout = descriptor_layout,
            .pipeline_layout = pipeline_layout,
            .descriptor_pool = descriptor_pool,
            .descriptor_set = descriptor_set,

            .buffers = std.AutoHashMap(u32, Buffer).init(allocator),
            .buffer_id_pool = IdPool.init(allocator, 0),
            .buffer_deleter = buffer_deleter,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.buffers.iterator();
        while (iterator.next()) |buffer| {
            buffer.value_ptr.deinit();
        }

        vk.vkd.destroyDescriptorPool(self.device, self.descriptor_pool, null);
        vk.vkd.destroyPipelineLayout(self.device, self.pipeline_layout, null);
        vk.vkd.destroyDescriptorSetLayout(self.device, self.descriptor_layout, null);

        self.buffers.deinit();
        self.buffer_id_pool.deinit();
        self.buffer_deleter.deinit();
    }

    //TODO use VMA or alternative
    fn findMemoryTypeIndex(self: Self, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.memory_properties.memory_types[0..self.memory_properties.memory_type_count]) |memory_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(u5, i)) != 0 and memory_type.property_flags.contains(flags)) {
                return @truncate(u32, i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    //TODO: track memory allocations
    pub fn allocate(self: Self, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try vk.vkd.allocateMemory(self.device, .{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }

    pub fn createBuffer(
        self: *Self,
        size: u32,
        usage: vk.BufferUsageFlags,
        memory_type: vk.MemoryPropertyFlags,
    ) !u32 {
        var id = self.buffer_id_pool.get();
        try self.buffers.put(id, try Buffer.init(self, size, usage, memory_type));
        return id;
    }

    pub fn createBufferFill(
        self: *Self,
        size: u32,
        usage: vk.BufferUsageFlags,
        memory_type: vk.MemoryPropertyFlags,
        comptime DataType: type,
        data: []const DataType,
    ) !u32 {
        var id = self.buffer_id_pool.get();
        var buffer = try Buffer.init(self, size, usage, memory_type);
        try buffer.fill(DataType, data);
        try self.buffers.put(id, buffer);
        return id;
    }

    pub fn destoryBuffer(self: *Self, id: u32) void {
        //TODO add it to a delete queue
        var buffer_optional = self.buffers.fetchRemove(id);

        if (buffer_optional) |buffer| {
            self.buffer_deleter.append(self.current_frame, buffer.value);
            self.buffer_id_pool.free(id);
        }
    }

    pub fn getBuffer(self: Self, id: u32) ?Buffer {
        return self.buffers.get(id);
    }

    pub fn flushResources(self: *Self) void {
        self.buffer_deleter.flush(self.current_frame);
    }
};
