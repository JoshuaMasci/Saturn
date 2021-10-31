const std = @import("std");

const vk = @import("vk.zig");
usingnamespace @import("device.zig");

pub const Buffer = struct {
    const Self = @This();

    device: Device,
    handle: vk.Buffer,
    memory: vk.DeviceMemory,
    size: u32,
    usage: vk.BufferUsageFlags,

    pub fn init(device: Device, size: u32, usage: vk.BufferUsageFlags, memory_type: vk.MemoryPropertyFlags) !Self {
        const buffer = try device.dispatch.createBuffer(
            device.handle,
            .{
                .flags = .{},
                .size = size,
                .usage = usage,
                .sharing_mode = .exclusive,
                .queue_family_index_count = 0,
                .p_queue_family_indices = undefined,
            },
            null,
        );
        const mem_reqs = device.dispatch.getBufferMemoryRequirements(device.handle, buffer);
        const memory = try device.allocate_memory(mem_reqs, memory_type);
        try device.dispatch.bindBufferMemory(device.handle, buffer, memory, 0);

        return Self{
            .device = device,
            .handle = buffer,
            .memory = memory,
            .size = size,
            .usage = usage,
        };
    }

    pub fn deinit(self: Self) void {
        self.device.dispatch.destroyBuffer(self.device.handle, self.handle, null);
        self.device.free_memory(self.memory);
    }

    pub fn fill(
        self: Self,
        comptime DataType: type,
        data: []const DataType,
    ) !void {
        //TODO staging buffers and bound checks
        var gpu_memory = try self.device.dispatch.mapMemory(self.device.handle, self.memory, 0, vk.WHOLE_SIZE, .{});
        var gpu_slice = @ptrCast([*]DataType, @alignCast(@alignOf(DataType), gpu_memory));
        defer self.device.dispatch.unmapMemory(self.device.handle, self.memory);
        std.mem.copy(DataType, gpu_slice[0..data.len], data);
    }
};
