const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

const vk = @import("vk.zig");

usingnamespace @import("device_resources.zig");

pub const Buffer = struct {
    const Self = @This();

    device: vk.Device,

    handle: vk.Buffer,
    memory: vk.DeviceMemory,

    size: u32,
    usage: vk.BufferUsageFlags,

    pub fn init(device: *DeviceResources, size: u32, usage: vk.BufferUsageFlags, memory_type: vk.MemoryPropertyFlags) !Self {
        const buffer = try vk.vkd.createBuffer(device.device, .{
            .flags = .{},
            .size = size,
            .usage = usage,
            .sharing_mode = .exclusive,
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
        }, null);
        const mem_reqs = vk.vkd.getBufferMemoryRequirements(device.device, buffer);
        const memory = try device.allocate(mem_reqs, memory_type);
        try vk.vkd.bindBufferMemory(device.device, buffer, memory, 0);

        return Self{
            .device = device.device,
            .handle = buffer,
            .memory = memory,
            .size = size,
            .usage = usage,
        };
    }

    pub fn deinit(self: Self) void {
        vk.vkd.destroyBuffer(self.device, self.handle, null);
        vk.vkd.freeMemory(self.device, self.memory, null);
    }

    pub fn fill(
        self: Self,
        comptime DataType: type,
        data: []const DataType,
    ) !void {
        //TODO staging buffers and bound checks
        var gpu_memory = try vk.vkd.mapMemory(self.device, self.memory, 0, vk.WHOLE_SIZE, .{});
        var gpu_slice = @ptrCast([*]DataType, @alignCast(@alignOf(DataType), gpu_memory));
        defer vk.vkd.unmapMemory(self.device, self.memory);
        std.mem.copy(DataType, gpu_slice[0..data.len], data);
    }
};
