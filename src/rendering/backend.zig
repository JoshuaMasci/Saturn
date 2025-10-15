const std = @import("std");

pub const BufferHandle = u16;
pub const TextureHandle = u16;
pub const AccelerationStructureHandle = u16;

pub const MemoryLocation = enum {
    gpu,
    cpu_to_gpu,
    gpu_to_cpu,
};

pub const BufferUsage = packed struct(u32) {
    transfer: bool = false,
    uniform: bool = false,
    storage: bool = false,
    index: bool = false,
    vertex: bool = false,
    indirect: bool = false,
    acceleration_structure: bool = false,
};

pub const BufferDescription = struct {
    name: ?[]const u8 = null,
    usage: BufferUsage,
    size: usize,
    alignment: ?u32 = null,
    location: MemoryLocation = .gpu,
};

const Self = @This();

//Buffer Functions
pub const BufferCreateError = error{out_of_memory};

pub fn createBuffer(self: *Self, desc: BufferDescription) BufferCreateError!BufferHandle {
    _ = desc; // autofix
    _ = self; // autofix
}
pub fn destroyBuffer(self: *Self, handle: BufferHandle) void {
    _ = self; // autofix
    _ = handle; // autofix
}
pub fn getBufferMappedByteSlice(self: *Self, handle: BufferHandle) ?[]u8 {
    _ = self; // autofix
    _ = handle; // autofix
    return null;
}

// Upload Functions
pub fn writeBuffer(
    self: *Self,
    buffer_handle: BufferHandle,
    buffer_offset: usize,
    data: []const u8,
) void {
    _ = buffer_handle; // autofix
    _ = buffer_offset; // autofix
    _ = data; // autofix
    _ = self; // autofix
}

pub const RenderError = error{};
pub fn render(self: *Self) RenderError!void {
    _ = self; // autofix
}

//Util Functions
pub fn createBufferInit(self: *Self, desc: BufferDescription, data: []const u8) BufferCreateError!BufferHandle {
    const buffer = try self.createBuffer(desc);
    errdefer self.destroyBuffer(buffer);

    if (self.getBufferMappedByteSlice(buffer)) |buffer_slice| {
        std.debug.assert(buffer_slice.len >= data.len);
        @memcpy(buffer_slice[0..data.len], data);
    } else {
        self.writeBuffer(buffer, 0, data);
    }

    return buffer;
}
