const std = @import("std");
const vk = @import("vulkan");

const Device = @import("vulkan/device.zig");

const DeviceAllocator = @import("vulkan/device_allocator.zig");
const TransferQueue = @import("vulkan/transfer_queue.zig");
const Buffer = @import("vulkan/buffer.zig");
const Image = @import("vulkan/image.zig");
const IdPool = @import("id_pool.zig");

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

//TODO: create empty buffer and images
// fn writeNullDescriptor(allocator: std.mem.Allocator, device: *Device, binding_counts: BindingCount, descriptor_set: vk.DescriptorSet) !void {
//     var descriptor_writes = try std.ArrayList(vk.WriteDescriptorSet).initCapacity(allocator, binding_counts.storage_buffer);
//     defer descriptor_writes.deinit();
//     var null_buffer_info = &vk.DescriptorBufferInfo{};
// }

//Bindless descriptor
const DescriptorSet = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    binding_counts: BindingCount,
    device: *Device,
    layout: vk.DescriptorSetLayout,
    pool: vk.DescriptorPool,
    set: vk.DescriptorSet,
    storage_buffer_indices: IdPool,

    fn init(allocator: std.mem.Allocator, device: *Device, binding_counts: BindingCount) !Self {
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
            .allocator = allocator,
            .binding_counts = binding_counts,
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

//Manages creation and descruction of all pipelines (except ray-tracing)
const PipelineCache = struct {};

pub const RenderDevice = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    device: *Device,
    device_allocator: *DeviceAllocator,
    transfer_queue: *TransferQueue,
    descriptor_set: DescriptorSet,
    pipeline_layout: vk.PipelineLayout,
    pipeline_cache: PipelineCache,

    pub fn init(allocator: std.mem.Allocator, device: *Device) !Self {
        var device_allocator = try allocator.create(DeviceAllocator);
        device_allocator.* = DeviceAllocator.init(device);

        var transfer_queue = try allocator.create(TransferQueue);
        transfer_queue.* = TransferQueue.init(allocator, device, device_allocator);

        // var empty_buffer = try Buffer.init(
        //     device,
        //     device_allocator,
        //     .{
        //         .size = 16,
        //         .usage = .{ .storage_buffer_bit = true },
        //         .memory_usage = .gpu_only,
        //     },
        // );

        var empty_image = try Image.init(device, device_allocator, .{
            .size = .{ 1, 1 },
            .format = .r8g8b8a8_unorm,
            .usage = .{ .storage_bit = true },
            .memory_usage = .gpu_only,
        });
        transfer_queue.copyToImage(empty_image, u8, &[_]u8{ 0, 0, 0, 0 });

        var descriptor_set = try DescriptorSet.init(allocator, device, .{ .storage_buffer = 4096 });

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
            .device_allocator = device_allocator,
            .transfer_queue = transfer_queue,
            .descriptor_set = descriptor_set,
            .pipeline_layout = pipeline_layout,
            .pipeline_cache = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.base.destroyPipelineLayout(self.device.handle, self.pipeline_layout, null);
        self.descriptor_set.deinit();

        self.transfer_queue.deinit();
        self.allocator.destroy(self.transfer_queue);

        self.device_allocator.deinit();
        self.allocator.destroy(self.device_allocator);
    }

    pub fn createBuffer(self: *Self, description: Buffer.Description) !Buffer {
        return try Buffer.init(self.device, self.device_allocator, description);
    }

    pub fn destroyBuffer(self: *Self, buffer: Buffer) void {
        _ = self;
        return buffer.deinit();
    }

    pub fn fillBuffer(self: *Self, buffer: Buffer, comptime DataType: type, data: []const DataType) !void {
        //TODO: transfer queue!!!

        var gpu_memory = try self.device.base.mapMemory(self.device.handle, buffer.allocation.memory, buffer.allocation.offset, vk.WHOLE_SIZE, .{});
        defer self.device.base.unmapMemory(self.device.handle, buffer.allocation.memory);

        var gpu_slice = @ptrCast([*]DataType, @alignCast(@alignOf(DataType), gpu_memory));
        std.mem.copy(DataType, gpu_slice[0..data.len], data);
    }

    pub fn createImage(self: *Self, description: Image.Description) !Image {
        return try Image.init(self.device, self.device_allocator, description);
    }

    pub fn destroyImage(self: *Self, image: Image) void {
        _ = self;
        image.deinit();
    }
};
