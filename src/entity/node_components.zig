const std = @import("std");

const type_id = @import("../type_id.zig");

const Self = @This();

const ComponetMap = std.AutoArrayHashMap(type_id.TypeId, struct { ptr: *anyopaque, vtable: *const VTable });

allocator: std.mem.Allocator,
components: ComponetMap,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .components = ComponetMap.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.components.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.vtable.free_ptr(entry.value_ptr.ptr, self.allocator);
    }
    self.components.deinit();
}

pub fn add(self: *Self, system: anytype) void {
    const T = @TypeOf(system);
    const id = type_id.typeId(T);
    const ptr = self.allocator.create(T) catch |err| std.debug.panic("Failed to allocate {s}: {}", .{ @typeName(T), err });
    ptr.* = system;
    self.components.put(id, .{ .ptr = ptr, .vtable = VTable.implVTable(T) }) catch |err| std.debug.panic("Failed to append {s}: {}", .{ @typeName(T), err });
}

pub fn remove(self: *Self, comptime T: type) bool {
    const id = type_id.typeId(T);
    if (self.components.fetchSwapRemove(id)) |entry| {
        entry.value.vtable.free_ptr(entry.value.ptr, self.allocator);
        return true;
    }
    return false;
}

pub fn get(self: *Self, comptime T: type) ?*T {
    const id = type_id.typeId(T);
    if (self.components.get(id)) |entry| {
        return @ptrCast(@alignCast(entry.ptr));
    }
    return null;
}

const VTable = struct {
    free_ptr: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,

    pub inline fn implVTable(comptime T: type) *const VTable {
        const functions = implVTableFunctions(T);
        return &VTable{
            .free_ptr = &functions.freePtrWrapper,
        };
    }

    fn implVTableFunctions(comptime T: type) type {
        return struct {
            // Wrapper functions
            fn freePtrWrapper(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                allocator.destroy(self);
            }
        };
    }
};
