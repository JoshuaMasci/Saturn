const std = @import("std");

const World = @import("world.zig");
const Entity = @import("entity.zig");
const UpdateStage = @import("universe.zig").UpdateStage;

const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub fn deinit(self: Self) void {
    self.vtable.deinit(self.ptr);
}

pub fn free(self: Self, allocator: std.mem.Allocator) void {
    self.vtable.free_ptr(self.ptr, allocator);
}

pub fn updateParallel(self: Self, stage: UpdateStage, entity: *Entity, world: *const World, delta_time: f32) void {
    self.vtable.updateParallel(self.ptr, stage, entity, world, delta_time);
}

pub fn updateExclusive(self: Self, stage: UpdateStage, entity: *Entity, world: *World, delta_time: f32) void {
    self.vtable.updateExclusive(self.ptr, stage, entity, world, delta_time);
}

pub const VTable = struct {
    deinit: *const fn (ctx: *anyopaque) void,
    updateParallel: *const fn (ctx: *anyopaque, stage: UpdateStage, entity: *Entity, world: *const World, delta_time: f32) void,
    updateExclusive: *const fn (ctx: *anyopaque, stage: UpdateStage, entity: *Entity, world: *World, delta_time: f32) void,
    free_ptr: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,

    pub inline fn implVTable(comptime T: type) *const VTable {
        const functions = implVTableFunctions(T);
        return &VTable{
            .deinit = &functions.deinitWrapper,
            .updateParallel = &functions.updateParallel,
            .updateExclusive = &functions.updateExclusive,
            .free_ptr = &functions.freePtrWrapper,
        };
    }

    fn implVTableFunctions(comptime T: type) type {
        return struct {
            // Wrapper functions
            fn deinitWrapper(ctx: *anyopaque) void {
                var self: *T = @ptrCast(@alignCast(ctx));
                self.deinit();
            }

            fn updateParallel(ctx: *anyopaque, stage: UpdateStage, entity: *Entity, world: *const World, delta_time: f32) void {
                var self: *T = @ptrCast(@alignCast(ctx));
                self.updateParallel(stage, entity, world, delta_time);
            }

            fn updateExclusive(ctx: *anyopaque, stage: UpdateStage, entity: *Entity, world: *World, delta_time: f32) void {
                var self: *T = @ptrCast(@alignCast(ctx));
                self.updateExclusive(stage, entity, world, delta_time);
            }

            fn freePtrWrapper(ctx: *anyopaque, allocator: std.mem.Allocator) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                allocator.destroy(self);
            }
        };
    }
};

pub const Systems = struct {
    const type_id = @import("../type_id.zig");

    allocator: std.mem.Allocator,
    systems: std.AutoArrayHashMap(type_id.TypeId, Self),

    pub fn init(allocator: std.mem.Allocator) Systems {
        return .{
            .allocator = allocator,
            .systems = std.AutoArrayHashMap(type_id.TypeId, Self).init(allocator),
        };
    }

    pub fn deinit(self: *Systems) void {
        var iter = self.systems.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
            entry.value_ptr.free(self.allocator);
        }
        self.systems.deinit();
    }

    pub fn add(self: *Systems, system: anytype) void {
        const T = @TypeOf(system);
        const id = type_id.typeId(T);
        const vtable = VTable.implVTable(T);
        const ptr = self.allocator.create(T) catch |err| std.debug.panic("Failed to allocate {s}: {}", .{ @typeName(T), err });
        ptr.* = system;
        self.systems.put(id, .{
            .ptr = ptr,
            .vtable = vtable,
        }) catch |err| std.debug.panic("Failed to append {s}: {}", .{ @typeName(T), err });
    }

    pub fn remove(self: *Systems, comptime T: type) bool {
        const id = type_id.typeId(T);
        if (self.systems.fetchSwapRemove(id)) |system| {
            system.value.deinit();
            system.value.free(self.allocator);
            return true;
        }
        return false;
    }

    pub fn get(self: *Systems, comptime T: type) ?*T {
        const id = type_id.typeId(T);
        if (self.systems.get(id)) |system| {
            return @ptrCast(@alignCast(system.ptr));
        }
        return null;
    }

    pub fn updateParallel(self: *Systems, stage: UpdateStage, entity: *Entity, world: *const World, delta_time: f32) void {
        const systems = self.systems.values();

        var temp_systems16: [16]Self = undefined;
        std.debug.assert(systems.len <= temp_systems16.len);
        const temp_systems = temp_systems16[0..systems.len];
        @memcpy(temp_systems, systems);

        for (temp_systems) |system| {
            system.updateParallel(stage, entity, world, delta_time);
        }
    }

    pub fn updateExclusive(self: *Systems, stage: UpdateStage, entity: *Entity, world: *World, delta_time: f32) void {
        const systems = self.systems.values();

        var temp_systems16: [16]Self = undefined;
        std.debug.assert(systems.len <= temp_systems16.len);
        const temp_systems = temp_systems16[0..systems.len];
        @memcpy(temp_systems, systems);

        for (temp_systems) |system| {
            system.updateExclusive(stage, entity, world, delta_time);
        }
    }
};
