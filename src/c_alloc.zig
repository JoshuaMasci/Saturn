const std = @import("std");

pub var mem_allocator: ?std.mem.Allocator = null;
const Metadata = struct {
    size: usize,
    alignment: usize,
};

pub fn alloc(size: usize) callconv(.C) ?*anyopaque {
    return alignedAlloc(size, 64);
}

pub fn calloc(count: usize, size: usize) callconv(.C) ?*anyopaque {
    return alloc(count * size);
}

pub fn realloc(maybe_ptr: ?*anyopaque, new_size: usize) callconv(.C) ?*anyopaque {
    if (maybe_ptr) |data_ptr| {
        const data_ptr_int: usize = @intFromPtr(data_ptr);
        const allocation_ptr: [*]u8 = @ptrFromInt(data_ptr_int - @sizeOf(Metadata));
        const metadata_ptr: *Metadata = @ptrCast(@alignCast(allocation_ptr));
        return reallocate(maybe_ptr, metadata_ptr.size + @sizeOf(Metadata), new_size);
    }
    return null;
}

pub fn alignedAlloc(size: usize, alignment: usize) callconv(.C) ?*anyopaque {
    if (mem_allocator) |allocator| {
        const allocation_size = size + alignment;

        const allocation: []u8 = switch (alignment) {
            16 => allocator.alignedAlloc(u8, 16, allocation_size),
            32 => allocator.alignedAlloc(u8, 32, allocation_size),
            64 => allocator.alignedAlloc(u8, 64, allocation_size),
            else => |x| std.debug.panic("Unsupported memory aligment: {}", .{x}),
        } catch return null;

        const data_ptr_int: usize = @as(usize, @intFromPtr(allocation.ptr)) + alignment;
        const data_ptr: *u8 = @ptrFromInt(data_ptr_int);
        const metadata_ptr: *Metadata = @ptrFromInt(data_ptr_int - @sizeOf(Metadata));
        metadata_ptr.size = size;
        metadata_ptr.alignment = alignment;

        return data_ptr;
    }
    return null;
}

pub fn reallocate(maybe_ptr: ?*anyopaque, old_size: usize, new_size: usize) callconv(.C) ?*anyopaque {
    if (maybe_ptr) |data_ptr| {
        if (mem_allocator) |allocator| {
            const data_ptr_int: usize = @intFromPtr(data_ptr);
            const metadata_ptr: *Metadata = @ptrFromInt(data_ptr_int - @sizeOf(Metadata));
            const allocation_ptr: [*]u8 = @ptrFromInt(data_ptr_int - metadata_ptr.alignment);
            const allocation_size: usize = metadata_ptr.size + metadata_ptr.alignment;

            if (old_size != metadata_ptr.size) {
                std.log.warn("Expected memory size({}) doesn't match memory's metadata({}), there may be a bug in the allocator", .{ old_size, metadata_ptr.size });
            }

            const new_allocation_size = new_size + metadata_ptr.alignment;

            // Try to resize current buffer
            const resized: bool = switch (metadata_ptr.alignment) {
                16 => allocator.resize(@as([*]align(16) u8, @alignCast(allocation_ptr))[0..allocation_size], new_allocation_size),
                32 => allocator.resize(@as([*]align(32) u8, @alignCast(allocation_ptr))[0..allocation_size], new_allocation_size),
                64 => allocator.resize(@as([*]align(64) u8, @alignCast(allocation_ptr))[0..allocation_size], new_allocation_size),
                else => |x| std.debug.panic("Unsupported memory aligment: {}", .{x}),
            };
            if (resized) {
                metadata_ptr.size = new_size;
                return data_ptr;
            }

            // If resize fails, try allocate and memcopy new buffer
            if (alignedAlloc(new_size, metadata_ptr.alignment)) |new_ptr| {
                defer free(maybe_ptr);

                if (new_size != 0) {
                    var old_data_ptr_bytes: [*]u8 = @ptrCast(data_ptr);
                    var new_data_ptr_bytes: [*]u8 = @ptrCast(new_ptr);
                    const copy_size = @min(metadata_ptr.size, new_size);
                    @memcpy(new_data_ptr_bytes[0..copy_size], old_data_ptr_bytes[0..copy_size]);
                    return new_ptr;
                } else {
                    return null;
                }
            }
        }
    }
    return alloc(new_size);
}

pub fn free(maybe_ptr: ?*anyopaque) callconv(.C) void {
    if (maybe_ptr) |data_ptr| {
        if (mem_allocator) |allocator| {
            const data_ptr_int: usize = @intFromPtr(data_ptr);
            const metadata_ptr: *Metadata = @ptrFromInt(data_ptr_int - @sizeOf(Metadata));
            const allocation_ptr: [*]u8 = @ptrFromInt(data_ptr_int - metadata_ptr.alignment);
            const allocation_size: usize = metadata_ptr.size + metadata_ptr.alignment;

            switch (metadata_ptr.alignment) {
                16 => allocator.free(@as([*]align(16) u8, @alignCast(allocation_ptr))[0..allocation_size]),
                32 => allocator.free(@as([*]align(32) u8, @alignCast(allocation_ptr))[0..allocation_size]),
                64 => allocator.free(@as([*]align(64) u8, @alignCast(allocation_ptr))[0..allocation_size]),
                else => |x| std.debug.panic("Unsupported memory aligment: {}", .{x}),
            }
        }
    }
}
