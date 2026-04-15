const std = @import("std");

const zm = @import("zmath");

const AllocationError = std.mem.Allocator.Error;

const containers = @import("containers.zig");
const SlotMap = containers.SlotMap;
const ArrayListSet = containers.ArrayListSet;
const ComponentMap = containers.ComponentMap;

const Transform = @import("transform.zig");

pub const NodePool = SlotMap(Node);
pub const NodeHandle = NodePool.Handle;
pub const NodeHandleSet = ArrayListSet(NodeHandle, null);

pub const EntityPool = SlotMap(Entity);
pub const EntityHandle = EntityPool.Handle;
pub const EntityHandleSet = ArrayListSet(EntityHandle, null);

pub const WorldPool = SlotMap(World);
pub const WorldHandle = WorldPool.Handle;

const EntityNodeHandle = struct { entity: EntityHandle, node: NodeHandle };

pub const Node = struct {
    handle: NodeHandle,

    name: ?[:0]const u8 = null, //TODO: allocate in an per entity arena?

    local_transform: Transform = .Identity,
    root_transform: ?Transform = null,

    parent: ?NodeHandle = null,
    children: NodeHandleSet = .empty,

    //Engine Components
    components: struct {
        static_mesh: ?@import("rendering/scene.zig").StaticMeshInstanceHandle = null,
    } = .{},
    //components: ComponentMap = .empty,
};

pub const Entity = struct {
    handle: EntityHandle,

    name: ?[:0]const u8 = null, //TODO: allocate in an per entity arena?

    world: ?WorldHandle = null,
    transform: Transform = .Identity,

    nodes: SlotMap(Node) = .empty,
    root_nodes: NodeHandleSet = .empty,

    //Engine Components
    components: struct {
        static_mesh: ?@import("rendering/scene.zig").StaticMeshInstanceHandle = null,
    } = .{},
    //components: ComponentMap = .empty,

    pub fn deinit(self: *Entity, gpa: std.mem.Allocator) void {
        var iter = self.nodes.iterator();
        while (iter.nextValue()) |node| {
            if (node.name) |name| gpa.free(name);
            node.children.deinit(gpa);
            //node.components.deinit(gpa);
        }
        self.nodes.deinit(gpa);

        //Component ptrs aren't freed, they should be stored in objects pools probably
        //self.components.deinit(gpa);

        if (self.name) |name| gpa.free(name);
    }
};

pub const World = struct {
    handle: WorldHandle,

    /// Name owned by the universe, cstring(null term) for convenience with ffi
    name: ?[:0]const u8 = null,

    entities: EntityHandleSet = .empty,

    //components: ComponentMap = .empty,

    pub fn deinit(self: *World, gpa: std.mem.Allocator) void {
        self.entities.deinit(gpa);

        //Component ptrs aren't freed, they should be stored in objects pools probably
        //self.components.deinit(gpa);

        if (self.name) |name| gpa.free(name);
    }
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
    var e_iter = self.entities.iterator();
    while (e_iter.nextValue()) |entity| {
        entity.deinit(self.gpa);
    }
    self.entities.deinit(self.gpa);

    var w_iter = self.worlds.iterator();
    while (w_iter.nextValue()) |world| {
        world.deinit(self.gpa);
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

pub fn destroyWorld(self: *Self, world_handle: WorldHandle, delete_entities: bool) void {
    if (self.worlds.remove(world_handle)) |world| {
        var world_mut: World = world;
        for (world_mut.entities.slice()) |entity_handle| {
            self.entities.getPtr(entity_handle).?.world = null;
            if (delete_entities) {
                self.destroyEntity(entity_handle);
            }
        }
        world_mut.deinit(self.gpa);
    }
}

pub fn createEntity(self: *Self, name_opt: ?[]const u8) AllocationError!EntityHandle {
    const name: ?[:0]const u8 = try self.dupeName(name_opt);
    errdefer if (name) |s| self.gpa.free(s);

    const handle = try self.entities.insert(self.gpa, .{
        .handle = undefined, //Chicken & Egg problem
        .name = name,
    });
    self.entities.getPtr(handle).?.handle = handle;

    return handle;
}

pub fn destroyEntity(self: *Self, entity_handle: EntityHandle) void {
    if (self.entities.remove(entity_handle)) |entity| {
        var entity_mut: Entity = entity;
        if (entity_mut.world) |world_handle| {
            _ = self.worlds.getPtr(world_handle).?.entities.remove(entity_handle);
        }
        entity_mut.deinit(self.gpa);
    }
}

fn dupeName(self: *Self, name_opt: ?[]const u8) AllocationError!?[:0]const u8 {
    if (name_opt) |z_name| {
        return try self.gpa.dupeZ(u8, z_name);
    }
    return null;
}
