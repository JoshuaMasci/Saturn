const std = @import("std");

const zm = @import("zmath");

const Transform = @import("transform.zig");

const containers = @import("containers.zig");
const SlotMap = containers.SlotMap;
const ArrayListSet = containers.ArrayListSet;

pub const AllocationError = std.mem.Allocator.Error;

pub const EntityPool = SlotMap(Entity);
pub const EntityHandle = EntityPool.Handle;
pub const EntityHandleSet = ArrayListSet(EntityHandle, null);

pub const WorldPool = SlotMap(World);
pub const WorldHandle = WorldPool.Handle;

pub const Entity = struct {
    handle: EntityHandle,

    /// Name owned by the universe, cstring(null term) for convenience with ffi
    name: ?[:0]const u8 = null,

    world: ?WorldHandle,
    local_transform: Transform,

    root: ?EntityHandle = null,
    parent: ?EntityHandle = null,
    children: EntityHandleSet = .empty,
    owned_world: ?WorldHandle = null,

    // Components
    //TODO: make it more configurable?
    scene_instance: ?@import("rendering/scene.zig").StaticMeshInstanceHandle = null,
};

pub const World = struct {
    handle: WorldHandle,

    /// Name owned by the universe, cstring(null term) for convenience with ffi
    name: ?[:0]const u8 = null,

    parent_entity: ?EntityHandle = null,
    entities: EntityHandleSet = .empty,
};

// Universe type
const Self = @This();

gpa: std.mem.Allocator,
entities: EntityPool = .empty,
worlds: WorldPool = .empty,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .gpa = allocator,
    };
}

pub fn deinit(self: *Self) void {
    var eit = self.entities.iterator();
    while (eit.nextValue()) |entity| {
        self.freeName(entity.name);
        entity.children.deinit(self.gpa);
    }
    self.entities.deinit(self.gpa);

    var wit = self.worlds.iterator();
    while (wit.nextValue()) |world| {
        self.freeName(world.name);
        world.entities.deinit(self.gpa);
    }
    self.worlds.deinit(self.gpa);
}

pub fn createWorld(self: *Self, name_opt: ?[]const u8) AllocationError!WorldHandle {
    const name: ?[:0]const u8 = try self.dupeName(name_opt);
    errdefer if (name) |s| self.gpa.free(s);

    const handle = try self.worlds.insert(self.gpa, .{
        .handle = undefined, //Chicken & Egg problem
        .name = name,
    });
    self.worlds.getPtr(handle).?.handle = handle;

    return handle;
}

pub fn destroyWorld(self: *Self, handle: WorldHandle, delete_entites: bool) void {
    if (self.worlds.remove(handle)) |world| {
        if (delete_entites) {}
        self.freeName(world.name);
        world.entities.deinit(self.gpa);
    }
}

pub fn createEntity(self: *Self, name_opt: ?[]const u8, world_handle: ?WorldHandle, parent_handle: ?EntityHandle, local_transform: Transform) !EntityHandle {
    const name: ?[:0]const u8 = try self.dupeName(name_opt);
    errdefer if (name) |s| self.gpa.free(s);

    const handle = try self.entities.insert(self.gpa, .{
        .handle = undefined, //Chicken & Egg problem
        .name = name,

        .world = world_handle,
        .local_transform = local_transform,
        .parent = parent_handle,
    });
    errdefer _ = self.entities.remove(handle);

    const entity = self.entities.getPtr(handle).?;
    entity.handle = handle;

    if (parent_handle) |p| {
        const parent = self.entities.getPtr(p).?;
        entity.root = parent.root;
        _ = try parent.children.insert(self.gpa, handle);
    } else {
        if (world_handle) |w| {
            const world = self.worlds.getPtr(w).?;
            _ = try world.entities.insert(self.gpa, handle);
        }
    }

    return handle;
}

pub fn updateEntityName(self: *Self, handle: EntityHandle, new_name: []const u8) AllocationError!void {
    const entity = self.entities.getPtr(handle).?;
    const old = entity.name;
    defer self.freeName(old);
    entity.name = try self.dupeName(new_name);
}

// Helper Functions for names, mostly here just to reduce duplicate code
// Ideally these would be inlined
fn dupeName(self: *Self, name_opt: ?[]const u8) AllocationError!?[:0]const u8 {
    if (name_opt) |z_name| {
        return try self.gpa.dupeZ(u8, z_name);
    }
    return null;
}

fn freeName(self: Self, name_opt: ?[:0]const u8) void {
    if (name_opt) |name| {
        self.gpa.free(name);
    }
}
