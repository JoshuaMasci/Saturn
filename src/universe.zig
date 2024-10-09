const std = @import("std");
const Transform = @import("transform.zig");
const ObjectPool = @import("object_pool.zig").ObjectPool;

//TODO: add name to all types (nodes, entities, worlds)

// Components
pub const NodeComponents = struct {
    model: ?void = null,
    collider: ?void = null,
};

pub const EntityComponents = struct {
    character: ?void = null,
    rigid_body: ?void = null,
};

// Systems
pub const EntitySystems = struct {};
pub const WorldSystems = struct {};

// Handles
pub const NodeHandle = NodePool.Handle;
pub const LocalEntityHandle = LocalEntityPool.Handle;
pub const GlobalEntityHandle = LocalEntityPool.Handle;
pub const WorldHandle = WorldPool.Handle;

// Containers
pub const NodePool = ObjectPool(u16, Node);
pub const LocalEntityPool = ObjectPool(u16, Entity);
pub const GlobalEntityPool = ObjectPool(u16, GlobalEntity);
pub const WorldPool = ObjectPool(u16, World);

pub const NodeList = std.BoundedArray(NodeHandle, 16);
fn removeFromList(list: *NodeList, node_handle: NodeHandle) bool {
    for (list.constSlice(), 0..) |list_handle, i| {
        if (list_handle == node_handle) {
            _ = list.swapRemove(i);
            return true;
        }
    }

    return false;
}

// Nodes
pub const Node = struct {
    const Self = @This();

    handle: NodeHandle,

    local_transform: Transform,
    components: NodeComponents,

    parent: ?NodeHandle,
    childen: NodeList,
};

pub const NodeSet = struct {
    const Self = @This();

    root_nodes: NodeList,
    pool: NodePool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .root_nodes = NodeList{},
            .pool = NodePool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.pool.deinit();
    }

    pub fn add(self: *Self, node: Node) !NodeHandle {
        const handle = try self.pool.insert(node);
        if (node.parent) |parent_handle| {
            if (self.pool.getPtr(parent_handle)) |parent| {
                parent.childen.append(handle) catch return error.child_node_list_full;
            } else {
                return error.invalid_parent_node;
            }
        } else {
            self.root_nodes.append(handle) catch return error.root_node_list_full;
        }

        return handle;
    }

    pub fn remove(self: *Self, node_handle: Node) !void {
        if (self.pool.remove(node_handle)) |node| {
            for (node.childen.slice()) |child_handle| {
                try self.remove(child_handle);
            }

            if (node.parent) |parent_handle| {
                if (self.pool.getPtr(parent_handle)) |parent| {
                    _ = removeFromList(&parent.childen, node_handle);
                } else {
                    return error.invalid_parent_node;
                }
            } else {
                _ = removeFromList(&self.root_nodes, node_handle);
            }
        }
    }
};

// Entity
pub const Entity = struct {
    const Self = @This();

    global_handle: GlobalEntityHandle,
    local_handle: ?LocalEntityHandle = null,

    name: ?std.ArrayList(u8) = null,
    transform: Transform = .{},
    nodes: NodeSet,

    components: EntityComponents = .{},
    systems: EntitySystems = .{},

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .global_handle = undefined,
            .nodes = NodeSet.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.name) |name| {
            name.deinit();
        }

        self.nodes.deinit();
    }
};

// World
pub const World = struct {
    const Self = @This();

    handle: WorldHandle,
    entities: LocalEntityPool,
    systems: WorldSystems = .{},

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .handle = undefined,
            .entities = LocalEntityPool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit_with_entries();
    }

    pub fn update(self: *Self, delta_time: f32) void {
        _ = self; // autofix
        _ = delta_time; // autofix
    }
};

// Universe
pub const GlobalEntity = struct {
    world_handle: WorldHandle,
    local_handle: LocalEntityHandle,
};

pub const Universe = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    entites: GlobalEntityPool,
    worlds: WorldPool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .entites = GlobalEntityPool.init(allocator),
            .worlds = WorldPool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entites.deinit();
        self.worlds.deinit_with_entries();
    }

    pub fn update(self: *Self, delta_time: f32) void {
        var iter = self.worlds.iterator();
        while (iter.next()) |world| {
            world.value_ptr.update(delta_time);
        }
    }

    pub fn create_world(self: *Self) !WorldHandle {
        const handle = try self.worlds.insert(World.init(self.allocator));
        self.worlds.getPtr(handle).?.handle = handle;
        return handle;
    }

    pub fn destory_world(self: *Self, world_handle: WorldHandle) void {
        if (self.worlds.remove(world_handle)) |world| {
            //Remove all entites from the global list
            var iter = world.entities.iterator();
            while (iter.next()) |entity| {
                _ = self.entites.remove(entity.value_ptr.global_handle);
            }

            world.deinit();
            return;
        }

        return error.invalid_world_handle;
    }

    pub fn create_entity(self: *Self, world_handle: WorldHandle) !GlobalEntityHandle {
        if (self.worlds.getPtr(world_handle)) |world| {
            const local_handle = try world.entities.insert(Entity.init(self.allocator));
            const global_handle = try self.entites.insert(.{ .world_handle = world_handle, .local_handle = local_handle });
            const entity_ptr = world.entities.getPtr(local_handle).?;
            entity_ptr.local_handle = local_handle;
            entity_ptr.global_handle = global_handle;
            return global_handle;
        }

        return error.invalid_world_handle;
    }

    pub fn get_entity_world(self: Self, entity_handle: GlobalEntityHandle) ?WorldHandle {
        if (self.entites.get(entity_handle)) |entity| {
            return entity.world_handle;
        }

        return null;
    }
};
