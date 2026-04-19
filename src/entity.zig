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

pub const EntityMap = SlotMap(*Entity);
pub const EntityHandle = EntityMap.Handle;
pub const EntityHandleSet = ArrayListSet(EntityHandle, null);
pub const EntityPool = std.heap.MemoryPool(Entity);

pub const WorldMap = SlotMap(*World);
pub const WorldHandle = WorldMap.Handle;
pub const WorldPool = std.heap.MemoryPool(World);

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
        if (self.name) |name| gpa.free(name);
        while (iter.nextValue()) |node| {
            if (node.name) |name| gpa.free(name);
            node.children.deinit(gpa);
            //node.components.deinit(gpa);
        }
        self.nodes.deinit(gpa);
        self.root_nodes.deinit(gpa);

        //Component ptrs aren't freed, they should be stored in objects pools probably
        //self.components.deinit(gpa);
    }

    pub fn createNode(self: *Entity, gpa: std.mem.Allocator, name_opt: ?[]const u8, parent_handle: ?NodeHandle) AllocationError!NodeHandle {
        const name: ?[:0]const u8 = if (name_opt) |n| try gpa.dupeZ(u8, n) else null;
        errdefer if (name) |s| gpa.free(s);

        const handle = try self.nodes.insert(gpa, .{
            .handle = undefined,
            .name = name,
            .parent = parent_handle,
        });
        self.nodes.getPtr(handle).?.handle = handle;

        if (parent_handle) |ph| {
            const parent_node = self.nodes.getPtr(ph) orelse return handle;
            _ = try parent_node.children.insert(gpa, handle);
        } else {
            _ = try self.root_nodes.insert(gpa, handle);
        }

        return handle;
    }

    pub fn destroyNode(self: *Entity, gpa: std.mem.Allocator, node_handle: NodeHandle, reparent_children: bool) void {
        const node = self.nodes.getPtr(node_handle) orelse return;
        const parent = node.parent;

        if (reparent_children) {
            const children_copy = node.children.slice();
            for (children_copy) |child_handle| {
                if (self.nodes.getPtr(child_handle)) |child| {
                    child.parent = parent;
                }
                if (parent) |ph| {
                    if (self.nodes.getPtr(ph)) |parent_node| {
                        parent_node.children.insert(gpa, child_handle) catch {};
                    }
                } else {
                    self.root_nodes.insert(gpa, child_handle) catch {};
                }
            }
        } else {
            const children_copy = node.children.slice();
            var to_delete = std.ArrayList(NodeHandle).init(gpa);
            defer to_delete.deinit();
            collectChildren(self, children_copy, &to_delete) catch {};
            for (to_delete.items) |h| {
                if (self.nodes.remove(h)) |n| {
                    var n_mut: Node = n;
                    if (n_mut.name) |nm| gpa.free(nm);
                    n_mut.children.deinit(gpa);
                }
            }
        }

        if (parent) |ph| {
            if (self.nodes.getPtr(ph)) |parent_node| {
                _ = parent_node.children.remove(node_handle);
            }
        } else {
            _ = self.root_nodes.remove(node_handle);
        }

        if (self.nodes.remove(node_handle)) |n| {
            var n_mut: Node = n;
            if (n_mut.name) |nm| gpa.free(nm);
            n_mut.children.deinit(gpa);
        }
    }

    fn collectChildren(self: *Entity, handles: []const NodeHandle, out: *std.ArrayList(NodeHandle)) AllocationError!void {
        for (handles) |h| {
            try out.append(h);
            if (self.nodes.getPtr(h)) |n| {
                try collectChildren(self, n.children.slice(), out);
            }
        }
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
entity_pool: EntityPool,
world_pool: WorldPool,

entities: EntityMap = .empty,
worlds: WorldMap = .empty,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .gpa = allocator,
        .entity_pool = .init(allocator),
        .world_pool = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var e_iter = self.entities.iterator();
    while (e_iter.nextValue()) |entity| {
        entity.*.deinit(self.gpa);
    }
    self.entities.deinit(self.gpa);
    self.entity_pool.deinit();

    var w_iter = self.worlds.iterator();
    while (w_iter.nextValue()) |world| {
        world.*.deinit(self.gpa);
    }
    self.worlds.deinit(self.gpa);
    self.world_pool.deinit();
}

pub fn createWorld(self: *Self, name_opt: ?[]const u8) AllocationError!WorldHandle {
    const world = try self.world_pool.create();
    errdefer self.world_pool.destroy(world);

    const handle = try self.worlds.insert(self.gpa, world);
    errdefer _ = self.worlds.remove(handle);

    const name: ?[:0]const u8 = try self.dupeName(name_opt);
    errdefer if (name) |s| self.gpa.free(s);

    world.* = .{
        .handle = handle,
        .name = name,
    };

    return handle;
}

pub fn destroyWorld(self: *Self, world_handle: WorldHandle, delete_entities: bool) void {
    if (self.worlds.remove(world_handle)) |world| {
        for (world.entities.slice()) |entity_handle| {
            self.entities.get(entity_handle).?.world = null;
            if (delete_entities) {
                self.destroyEntity(entity_handle);
            }
        }
        world.deinit(self.gpa);
    }
}

pub fn createEntity(self: *Self, name_opt: ?[]const u8, world_opt: ?WorldHandle) AllocationError!*Entity {
    const entity = try self.entity_pool.create();
    errdefer self.entity_pool.destroy(entity);

    const handle = try self.entities.insert(self.gpa, entity);
    errdefer _ = self.entities.remove(handle);

    const name: ?[:0]const u8 = try self.dupeName(name_opt);
    errdefer if (name) |s| self.gpa.free(s);

    if (world_opt) |world| {
        const world_ptr = self.worlds.get(world).?;
        _ = try world_ptr.entities.insert(self.gpa, handle);
    }

    entity.* = .{
        .handle = handle,
        .name = name,
        .world = world_opt,
    };

    return entity;
}

pub fn destroyEntity(self: *Self, entity_handle: EntityHandle) void {
    if (self.entities.remove(entity_handle)) |entity| {
        if (entity.world) |world_handle| {
            _ = self.worlds.get(world_handle).?.entities.remove(entity_handle);
        }
        entity.deinit(self.gpa);
    }
}

fn dupeName(self: *Self, name_opt: ?[]const u8) AllocationError!?[:0]const u8 {
    if (name_opt) |z_name| {
        return try self.gpa.dupeZ(u8, z_name);
    }
    return null;
}
