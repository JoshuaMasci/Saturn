const std = @import("std");

const type_id = @import("../type_id.zig");

const Self = @This();

allocator: std.mem.Allocator,
components: std.AutoArrayHashMap(type_id.TypeId, *anyopaque),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .components = std.AutoArrayHashMap(type_id.TypeId, Self).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.components.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit();
        entry.value_ptr.free(self.allocator);
    }
    self.components.deinit();
}

pub fn add(self: *Self, system: anytype) void {
    const T = @TypeOf(system);
    const id = type_id.typeId(T);
    const ptr = self.allocator.create(T) catch |err| std.debug.panic("Failed to allocate {s}: {}", .{ @typeName(T), err });
    ptr.* = system;
    self.components.put(id, ptr) catch |err| std.debug.panic("Failed to append {s}: {}", .{ @typeName(T), err });
}

pub fn remove(self: *Self, comptime T: type) bool {
    const id = type_id.typeId(T);
    if (self.components.fetchSwapRemove(id)) |opaque_ptr| {
        const ptr: *T = @ptrCast(@alignCast(opaque_ptr));
        self.allocator.destroy(ptr);
        return true;
    }
    return false;
}

pub fn get(self: *Self, comptime T: type) ?*T {
    const id = type_id.typeId(T);
    if (self.components.get(id)) |system| {
        return @ptrCast(@alignCast(system.ptr));
    }
    return null;
}
