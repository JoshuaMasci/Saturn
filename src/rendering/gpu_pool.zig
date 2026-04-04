const std = @import("std");

const saturn = @import("../root.zig");
const TransferQueue = @import("transfer_queue.zig");

pub fn GpuPool(comptime T: type) type {
    return struct {
        const This = @This();

        allocator: std.mem.Allocator,
        device: saturn.DeviceInterface,
        buffer: saturn.BufferHandle,

        device_address: ?u64,
        storage_binding: ?u32,

        element_count: usize,
        free_list: std.DynamicBitSetUnmanaged,

        default: T,
        dirty: std.DynamicBitSetUnmanaged,
        staging: []T,

        pub fn init(
            allocator: std.mem.Allocator,
            device: saturn.DeviceInterface,
            name: [:0]const u8,
            element_count: usize,
            buffer_usage: saturn.BufferUsage,
            default: T,
        ) saturn.Error!This {
            const buffer = try device.createBuffer(.{
                .name = name,
                .size = element_count * @sizeOf(T),
                .usage = buffer_usage,
                .memory = .gpu_only,
            });
            errdefer device.destroyBuffer(buffer);

            const buffer_info = device.getBufferInfo(buffer).?;

            var free_list = try std.DynamicBitSetUnmanaged.initFull(allocator, element_count);
            errdefer free_list.deinit(allocator);

            var dirty = try std.DynamicBitSetUnmanaged.initEmpty(allocator, element_count);
            errdefer dirty.deinit(allocator);

            const staging = try allocator.alloc(T, element_count);
            errdefer allocator.free(staging);
            @memset(staging, default);

            return .{
                .allocator = allocator,
                .device = device,
                .buffer = buffer,
                .device_address = buffer_info.device_address,
                .storage_binding = buffer_info.storage,
                .element_count = element_count,
                .free_list = free_list,
                .default = default,
                .dirty = dirty,
                .staging = staging,
            };
        }

        pub fn deinit(self: *This) void {
            self.allocator.free(self.staging);
            self.dirty.deinit(self.allocator);
            self.free_list.deinit(self.allocator);
            self.device.destroyBuffer(self.buffer);
        }

        pub fn alloc(self: *This) error{OutOfMemory}!u32 {
            const index = self.free_list.findFirstSet() orelse return error.OutOfMemory;
            self.free_list.unset(index);
            return @intCast(index);
        }

        pub fn free(self: *This, index: u32) void {
            self.free_list.set(index);
            self.stage(index, self.default);
        }

        pub fn deviceAddress(self: *const This, index: u32) u64 {
            return self.device_address + (@as(u64, index) * @sizeOf(T));
        }

        pub fn stage(self: *This, index: u32, value: T) void {
            self.staging[index] = value;
            self.dirty.set(index);
        }

        pub fn create(self: *This, value: T) !u32 {
            const index = try self.alloc();
            self.stage(index, value);
            return index;
        }

        pub fn flush(self: *This, transfer_queue: *TransferQueue) !void {
            var it = self.dirty.iterator(.{});
            while (it.next()) |index| {
                const byte_offset = @as(u64, index) * @sizeOf(T);
                try transfer_queue.addBufferUpload(self.buffer, byte_offset, std.mem.asBytes(&self.staging[index]));
            }
            self.dirty.setRangeValue(.{ .start = 0, .end = self.element_count }, false);
        }

        pub fn freeCount(self: *const This) usize {
            return self.free_list.count();
        }

        pub fn reset(self: *This) void {
            self.free_list.setRangeValue(.{ .start = 0, .end = self.element_count }, true);
            @memset(self.staging, self.default);
            self.dirty.setRangeValue(.{ .start = 0, .end = self.element_count }, true);
        }
    };
}
