const std = @import("std");

const vk = @import("vulkan");

const Backend = @import("vulkan/backend.zig");

pub fn GpuArrayList(comptime T: type) type {
    return struct {
        const This = @This();

        gpa: std.mem.Allocator,
        backend: *Backend,

        name: []const u8,
        usage: vk.BufferUsageFlags,

        cpu: std.ArrayList(T),
        gpu: Backend.BufferHandle,
        gpu_capacity: usize,

        pub fn init(
            gpa: std.mem.Allocator,
            backend: *Backend,
            name: []const u8,
            usage: vk.BufferUsageFlags,
            capacity: usize,
        ) !This {
            var cpu = try std.ArrayList(T).initCapacity(gpa, capacity);
            errdefer cpu.deinit(gpa);

            const gpu = try backend.createBuffer(
                name,
                capacity * @sizeOf(T),
                usage,
            );
            errdefer backend.destroyBuffer(gpu);

            return .{
                .gpa = gpa,
                .backend = backend,

                .name = name,
                .usage = usage,

                .cpu = cpu,
                .gpu = gpu,
                .gpu_capacity = capacity,
            };
        }

        pub fn deinit(self: *This) void {
            self.cpu.deinit(self.gpa);
            self.backend.destroyBuffer(self.gpu);
        }

        fn resize(self: *This, new_capacity: usize) !void {
            const old_gpu = self.gpu;

            const new_gpu = try self.backend.createBuffer(
                self.name,
                new_capacity * @sizeOf(T),
                self.usage,
            );

            const old_size = self.gpu_capacity * @sizeOf(T);
            if (old_size > 0) {
                const old_bytes = std.mem.sliceAsBytes(self.cpu.items[0..self.gpu_capacity]);
                try self.backend.getTransferQueue().writeBuffer(new_gpu, 0, old_bytes);
            }

            self.backend.destroyBuffer(old_gpu);

            self.gpu = new_gpu;
            self.gpu_capacity = new_capacity;
        }

        pub fn push(self: *This, item: T) !usize {
            const index = self.cpu.items.len;

            try self.cpu.append(self.gpa, item);

            if (self.cpu.items.len > self.gpu_capacity) {
                try self.resize(self.cpu.capacity);
            }

            const byte_offset = index * @sizeOf(T);
            const item_bytes = std.mem.asBytes(&item);
            try self.backend.getTransferQueue().writeBuffer(self.gpu, byte_offset, item_bytes);

            return index;
        }

        pub fn swapRemove(self: *This, index: usize) !?usize {
            if (index >= self.cpu.items.len) return null;

            const last_index = self.cpu.items.len - 1;

            if (index == last_index) {
                _ = self.cpu.pop();
                return null;
            }

            _ = self.cpu.swapRemove(index);

            const byte_offset = index * @sizeOf(T);
            const item_bytes = std.mem.asBytes(&self.cpu.items[index]);
            try self.backend.getTransferQueue().writeBuffer(self.gpu, byte_offset, item_bytes.*);

            return index;
        }

        pub fn shrinkRetainingCapacity(self: *This, new_len: usize) void {
            self.cpu.shrinkRetainingCapacity(new_len);
        }

        pub fn count(self: *const This) usize {
            return self.cpu.items.len;
        }
    };
}
