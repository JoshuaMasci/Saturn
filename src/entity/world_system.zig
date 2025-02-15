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

pub fn registerEntity(self: Self, world: *World, entity: *Entity) void {
    self.vtable.register_entity(self.ptr, world, entity);
}

pub fn deregisterEntity(self: Self, world: *World, entity: *Entity) void {
    self.vtable.deregister_entity(self.ptr, world, entity);
}

pub fn update(self: Self, stage: UpdateStage, world: *World, delta_time: f32) void {
    self.vtable.update(self.ptr, stage, world, delta_time);
}

pub const VTable = struct {
    deinit: *const fn (ctx: *anyopaque) void,
    register_entity: *const fn (ctx: *anyopaque, world: *World, entity: *Entity) void,
    deregister_entity: *const fn (ctx: *anyopaque, world: *World, entity: *Entity) void,
    update: *const fn (ctx: *anyopaque, stage: UpdateStage, world: *World, delta_time: f32) void,
    free_ptr: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,

    pub inline fn implVTable(comptime T: type) *const VTable {
        const functions = implVTableFunctions(T);
        return &VTable{
            .deinit = &functions.deinitWrapper,
            .register_entity = &functions.registerEntityWrapper,
            .deregister_entity = &functions.deregisterEntityWrapper,
            .update = &functions.updateWrapper,
            .free_ptr = &functions.freePtrWrapper,
        };
    }

    fn implVTableFunctions(comptime T: type) type {
        return struct {
            // Wrapper functions
            fn deinitWrapper(ctx: *anyopaque) void {
                if (std.meta.hasFn(T, "deinit")) {
                    var self: *T = @ptrCast(@alignCast(ctx));
                    self.deinit();
                }
            }

            fn registerEntityWrapper(ctx: *anyopaque, world: *World, entity: *Entity) void {
                if (std.meta.hasFn(T, "registerEntity")) {
                    var self: *T = @ptrCast(@alignCast(ctx));
                    self.registerEntity(world, entity);
                }
            }

            fn deregisterEntityWrapper(ctx: *anyopaque, world: *World, entity: *Entity) void {
                if (std.meta.hasFn(T, "deregisterEntity")) {
                    var self: *T = @ptrCast(@alignCast(ctx));
                    self.deregisterEntity(world, entity);
                }
            }

            fn updateWrapper(ctx: *anyopaque, stage: UpdateStage, world: *World, delta_time: f32) void {
                if (std.meta.hasFn(T, "update")) {
                    var self: *T = @ptrCast(@alignCast(ctx));
                    self.update(stage, world, delta_time);
                }
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

    pub fn registerEntity(self: *Systems, world: *World, entity: *Entity) void {
        var iter = self.systems.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.registerEntity(world, entity);
        }
    }

    pub fn deregisterEntity(self: *Systems, world: *World, entity: *Entity) void {
        var iter = self.systems.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deregisterEntity(world, entity);
        }
    }

    pub fn update(self: *Systems, temp_allocator: std.mem.Allocator, stage: UpdateStage, world: *World, delta_time: f32) void {
        const systems = self.systems.values();
        const temp_systems = temp_allocator.alloc(Self, systems.len) catch |err| std.debug.panic("Failed to allocate temp list: {}", .{err});
        defer temp_allocator.free(temp_systems);
        @memcpy(temp_systems, systems);

        for (temp_systems) |system| {
            system.update(stage, world, delta_time);
        }
    }
};
