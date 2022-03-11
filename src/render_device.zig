const std = @import("std");
const vk = @import("vulkan");

const Device = @import("vulkan/device.zig");

const DeviceAllocator = @import("vulkan/device_allocator.zig");
const TransferQueue = @import("vulkan/transfer_queue.zig");
const DescriptorSet = @import("vulkan/descriptor_set.zig");

const Buffer = @import("vulkan/buffer.zig");
const Image = @import("vulkan/image.zig");

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

        var empty_buffer = try Buffer.init(
            device,
            device_allocator,
            .{
                .size = 16,
                .usage = .{ .storage_buffer_bit = true },
                .memory_usage = .gpu_only,
            },
        );

        var empty_image = try Image.init(device, device_allocator, .{
            .size = .{ 1, 1 },
            .format = .r8g8b8a8_unorm,
            .usage = .{
                .storage_bit = true,
                .sampled_bit = true,
            },
            .memory_usage = .gpu_only,
        });
        transfer_queue.copyToImage(empty_image, u8, &[_]u8{ 0, 0, 0, 0 });

        var empty_sampler = try device.base.createSampler(
            device.handle,
            &.{
                .flags = .{},
                .mag_filter = .linear,
                .min_filter = .linear,
                .mipmap_mode = .linear,
                .address_mode_u = .clamp_to_border,
                .address_mode_v = .clamp_to_border,
                .address_mode_w = .clamp_to_border,
                .mip_lod_bias = 0.0,
                .anisotropy_enable = vk.FALSE,
                .max_anisotropy = 0.0,
                .compare_enable = vk.FALSE,
                .compare_op = .always,
                .min_lod = 0.0,
                .max_lod = 0.0,
                .border_color = .float_transparent_black,
                .unnormalized_coordinates = vk.FALSE,
            },
            null,
        );

        var descriptor_set = try DescriptorSet.init(allocator, device, empty_buffer, empty_image, empty_sampler, .{
            .storage_buffer = 4096,
            .storage_image = 4096,
            .sampled_image = 4096,
            .sampler = 32,
        });

        var descriptor_set_layouts = &[_]vk.DescriptorSetLayout{descriptor_set.layout};
        var push_constant_ranges = &[_]vk.PushConstantRange{.{
            .stage_flags = DescriptorSet.ALL_STAGES,
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
