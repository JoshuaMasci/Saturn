const vk = @import("vulkan");

const Device = @import("vulkan/device.zig");

pub fn ArrayBuffer(comptime T: type) type {
    const T_SIZE: usize = @sizeOf(T);

    return struct {
        const Self = @This();

        handle: Device.BufferHandle,

        pub fn init(device: *Device, count: usize, usage: vk.BufferUsageFlags) !Self {
            return .{ .handle = try device.createBuffer(T_SIZE * count, usage) };
        }

        pub fn deinit(self: Self, device: *Device) void {
            device.destroyBuffer(self.handle);
        }

        pub fn set(self: Self, device: *Device, index: usize, data: *T) void {
            _ = index; // autofix
            _ = data; // autofix
            const buffer = device.buffers.get(self.handle) orelse @panic("Failed to get buffer");
            _ = buffer; // autofix
        }
    };
}
