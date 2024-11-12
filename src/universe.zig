const std = @import("std");
const Transform = @import("transform.zig");
const ObjectPool = @import("object_pool.zig").ObjectPool;

const rendering_system = @import("rendering.zig");

pub const StaticMeshComponent = struct {
    visable: bool = true,
    mesh: rendering_system.StaticMeshHandle,
    material: rendering_system.MaterialHandle,
    instance: ?rendering_system.SceneInstanceHandle = null,
};

pub const RenderWorldSystem = struct {
    const Self = @This();

    scene: rendering_system.Scene,

    pub fn deinit(self: *Self) void {
        self.scene.deinit();
    }

    pub fn register_entity(self: *Self, data: EntityRegisterData) void {
        var iter = data.entity.node_pool.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.components.static_mesh) |*static_mesh_component| {
                const world_transform = data.entity.get_node_world_transform(entry.handle).?;
                const instance = self.scene.add_instace(static_mesh_component.mesh, static_mesh_component.material, &world_transform) catch std.debug.panic("Failed to add instance to scene", .{});
                static_mesh_component.instance = instance;
            }
        }
    }

    pub fn pre_render(self: *Self, world: *World) void {
        for (world.entities.values()) |*entity| {
            update_entity_instances(&self.scene, entity);
        }
    }

    fn update_entity_instances(scene: *rendering_system.Scene, entity: *const Entity) void {
        var iter = entity.node_pool.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.components.static_mesh) |*static_mesh_component| {
                if (static_mesh_component.instance) |instance| {
                    const root_transform = entity.get_node_root_transform(entry.handle).?;
                    const world_transform = entity.transform.transform_by(&root_transform);
                    scene.update_instance(instance, &world_transform);
                }
            }
        }
    }
};

// Components
pub const NodeComponents = struct {
    static_mesh: ?StaticMeshComponent = null,
    collider: ?void = null,
    light: ?void = null,
};
pub const NodeHandle = NodePool.Handle;
pub const NodePool = ObjectPool(u16, Node);

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

    parent: ?NodeHandle = null,
    childen: NodeList = .{},
};

// Entity
pub const Entity = struct {
    const Self = @This();

    pub const Handle = u32;
    var next_handle = std.atomic.Value(Handle).init(1);

    handle: Handle,
    world_handle: ?World.Handle = null,

    name: ?std.ArrayList(u8) = null,
    transform: Transform = .{},

    root_nodes: NodeList = .{},
    node_pool: NodePool,

    systems: EntitySystems = .{},

    pub fn init(allocator: std.mem.Allocator, systems: EntitySystems) Self {
        return .{
            .handle = next_handle.fetchAdd(1, .monotonic), //TODO: is this the correct atomic order?
            .node_pool = NodePool.init(allocator),
            .systems = systems,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.name) |name| {
            name.deinit();
        }

        self.node_pool.deinit();
        self.systems.deinit();
    }

    //Node functions
    pub fn add_node(
        self: *Self,
        parent: ?NodeHandle,
        local_transform: Transform,
        components: NodeComponents,
    ) !NodeHandle {
        const handle = try self.node_pool.insert(.{
            .parent = parent,
            .handle = undefined,
            .local_transform = local_transform,
            .components = components,
        });
        self.node_pool.getPtr(handle).?.handle = handle;

        if (parent) |parent_handle| {
            if (self.node_pool.getPtr(parent_handle)) |parent_node| {
                parent_node.childen.append(handle) catch return error.child_node_list_full;
            } else {
                return error.invalid_parent_node;
            }
        } else {
            self.root_nodes.append(handle) catch return error.root_node_list_full;
        }

        return handle;
    }

    pub fn remove_node(self: *Self, node_handle: NodeHandle) !void {
        if (self.node_pool.remove(node_handle)) |node| {
            for (node.childen.slice()) |child_handle| {
                try self.remove_node(child_handle);
            }

            if (node.parent) |parent_handle| {
                if (self.node_pool.getPtr(parent_handle)) |parent| {
                    _ = removeFromList(&parent.childen, node_handle);
                } else {
                    std.log.err("Node({}) had an invalid Parent({})", .{ node_handle, parent_handle });
                }
            } else {
                _ = removeFromList(&self.root_nodes, node_handle);
            }
        }
    }

    pub fn get_node_root_transform(self: Self, node_handle: NodeHandle) ?Transform {
        const node = self.node_pool.get(node_handle).?;
        var parent_handle: ?NodeHandle = node.parent;
        var total_transform: Transform = node.local_transform;
        while (parent_handle) |handle| {
            const parent_node = self.node_pool.getPtr(handle).?;
            parent_handle = parent_node.parent;
            total_transform = parent_node.local_transform.transform_by(&total_transform);
        }

        return total_transform;
    }

    //Update functions
    pub fn frame_start(self: *Self, delta_time: f32) void {
        self.systems.frame_start(self, delta_time);
    }

    pub fn pre_physics(self: *Self, delta_time: f32) void {
        self.systems.pre_physics(self, delta_time);
    }

    pub fn post_physics(self: *Self, delta_time: f32) void {
        self.systems.post_physics(self, delta_time);
    }

    pub fn pre_render(self: *Self) void {
        self.systems.pre_render(self);
    }

    pub fn frame_end(self: *Self) void {
        self.systems.frame_end(self);
    }

    pub fn add_to_world(self: *Self, world: *World) void {
        self.systems.add_to_world(self, world);
    }

    pub fn remove_from_world(self: *Self, world: *World) void {
        self.systems.remove_from_world(self, world);
    }

    pub fn get_node_world_transform(self: *const Self, node: NodeHandle) ?Transform {
        if (self.get_node_root_transform(node)) |root_transform| {
            return self.transform.transform_by(&root_transform);
        }
        return null;
    }
};

// World
pub const World = struct {
    const Self = @This();

    pub const Handle = u32;
    var next_handle = std.atomic.Value(Handle).init(1);

    allocator: std.mem.Allocator,
    handle: Handle,
    entities: std.AutoArrayHashMap(Entity.Handle, Entity),
    systems: WorldSystems = .{},

    pub fn init(allocator: std.mem.Allocator, systems: WorldSystems) !*Self {
        const self_ptr = try allocator.create(World);
        self_ptr.* = .{
            .allocator = allocator,
            .handle = undefined,
            .entities = std.AutoArrayHashMap(Entity.Handle, Entity).init(allocator),
            .systems = systems,
        };
        return self_ptr;
    }

    pub fn deinit(self: *Self) void {
        for (self.entities.values()) |*entity| {
            entity.deinit();
        }

        self.entities.deinit();
        self.systems.deinit();
        self.allocator.destroy(self);
    }

    pub fn update(self: *Self, delta_time: f32) void {
        // Frame Start
        {
            //TODO: run in parallel
            for (self.entities.values()) |*entity| {
                entity.systems.frame_start(entity, delta_time);
            }
            self.systems.frame_start(self, delta_time);
        }

        // Pre Physics
        {
            for (self.entities.values()) |*entity| {
                entity.systems.pre_physics(entity, delta_time);
            }

            self.systems.pre_physics(self, delta_time);
        }

        //TODO: simulate physics here

        // Post Physics
        {
            for (self.entities.values()) |*entity| {
                entity.systems.post_physics(entity, delta_time);
            }
            self.systems.post_physics(self, delta_time);
        }

        // Pre Render
        {
            for (self.entities.values()) |*entity| {
                entity.systems.pre_render(entity);
            }
            self.systems.pre_render(self);
        }

        //TODO: Submit Render Here???????

        // Frame End
        {
            for (self.entities.values()) |*entity| {
                entity.systems.frame_end(entity);
            }
            self.systems.frame_end(self);
        }
    }

    pub fn add_entity(self: *Self, entity: Entity) void {
        self.entities.put(entity.handle, entity) catch std.debug.panic("Failed to push entity to entity list", .{});
        self.systems.register_entity(self, self.entities.getPtr(entity.handle).?);
    }
};

// Universe
pub const Universe = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    worlds: std.AutoHashMap(World.Handle, *World),
    entity_locations: std.AutoHashMap(Entity.Handle, World.Handle),

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .worlds = std.AutoHashMap(World.Handle, *World).init(allocator),
            .entity_locations = std.AutoHashMap(Entity.Handle, World.Handle).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.worlds.valueIterator();
        while (iter.next()) |world| {
            world.*.deinit();
        }
        self.worlds.deinit();
        self.entity_locations.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) void {
        var iter = self.worlds.valueIterator();
        while (iter.next()) |world| {
            world.*.update(delta_time);
        }
    }

    pub fn add_world(self: *Self, world: *World) !World.Handle {
        std.debug.assert(!self.worlds.contains(world.handle));
        try self.worlds.put(world.handle, world);
        return world.handle;
    }

    pub fn remove_world(self: *Self, world_handle: World.Handle) ?World {
        std.debug.assert(self.worlds.contains(world_handle));
        if (self.worlds.fetchRemove(world_handle)) |entry| {
            for (entry.value.entities.values()) |entity| {
                _ = self.entity_locations.remove(entity.handle);
            }
            return entry.value;
        }
        return null;
    }
};

// Systems
pub const EntityUpdateData = struct { entity: *Entity, delta_time: f32 };
pub const EntityEventData = struct { world: *World, entity: *Entity };
pub const EntitySystems = struct {
    const Self = @This();

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn frame_start(self: *Self, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("frame_start", EntityUpdateData, self, .{ .entity = entity, .delta_time = delta_time });
    }

    pub fn pre_physics(self: *Self, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("pre_physics", EntityUpdateData, self, .{ .entity = entity, .delta_time = delta_time });
    }

    pub fn post_physics(self: *Self, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("post_physics", EntityUpdateData, self, .{ .entity = entity, .delta_time = delta_time });
    }

    pub fn pre_render(self: *Self, entity: *Entity) void {
        callMethodOnFieldsIfExists("pre_render", *Entity, self, entity);
    }

    pub fn frame_end(self: *Self, entity: *Entity) void {
        callMethodOnFieldsIfExists("frame_end", *Entity, self, entity);
    }
};

pub const WorldUpdateData = struct { world: *World, delta_time: f32 };
pub const EntityRegisterData = struct { world: *World, entity: *Entity };
pub const WorldSystems = struct {
    const Self = @This();

    render: ?RenderWorldSystem = null,

    pub fn deinit(self: *Self) void {
        if (self.render) |*render| {
            render.deinit();
        }
    }

    pub fn register_entity(self: *Self, world: *World, entity: *Entity) void {
        callMethodOnFieldsIfExists("register_entity", EntityRegisterData, self, .{ .world = world, .entity = entity });
    }

    pub fn frame_start(self: *Self, world: *World, delta_time: f32) void {
        callMethodOnFieldsIfExists("frame_start", WorldUpdateData, self, .{ .world = world, .delta_time = delta_time });
    }

    pub fn pre_physics(self: *Self, world: *World, delta_time: f32) void {
        callMethodOnFieldsIfExists("pre_physics", WorldUpdateData, self, .{ .world = world, .delta_time = delta_time });
    }

    pub fn post_physics(self: *Self, world: *World, delta_time: f32) void {
        callMethodOnFieldsIfExists("post_physics", WorldUpdateData, self, .{ .world = world, .delta_time = delta_time });
    }

    pub fn pre_render(self: *Self, world: *World) void {
        callMethodOnFieldsIfExists("pre_render", *World, self, world);
    }

    pub fn frame_end(self: *Self, world: *World) void {
        callMethodOnFieldsIfExists("frame_end", *World, self, world);
    }
};

fn callMethodOnFieldsIfExists(
    comptime method_name: []const u8,
    comptime Args: type,
    self: anytype,
    args: Args,
) void {
    const self_type = unwrapPointerType(@TypeOf(self)) orelse @compileError("self must be an ptr type");
    inline for (std.meta.fields(self_type)) |struct_field| {
        const field_type = unwrapOptionalType(struct_field.type) orelse @compileError("Field must be an optional type");
        if (comptime std.meta.hasMethod(field_type, method_name)) {
            const field_opt: *struct_field.type = &@field(self, struct_field.name);
            if (field_opt.*) |*field| {
                if (unwrapPointerType(field_type)) |base_field_type| {
                    const function = @field(base_field_type, method_name);
                    function(field.*, args);
                } else {
                    const function = @field(field_type, method_name);
                    function(field, args);
                }
            }
        }
    }
}

fn unwrapOptionalType(comptime T: type) ?type {
    switch (@typeInfo(T)) {
        .Optional => |option| return option.child,
        else => return null,
    }
}

fn unwrapPointerType(comptime T: type) ?type {
    switch (@typeInfo(T)) {
        .Pointer => |pointer| return pointer.child,
        else => return null,
    }
}
