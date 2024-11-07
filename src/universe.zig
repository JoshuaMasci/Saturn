const std = @import("std");
const Transform = @import("transform.zig");
const StableObjectPool = @import("stable_object_pool.zig").StableObjectPool;

const rendering_system = @import("rendering.zig");
//const render_scene = @import("render_scene.zig");

pub const StaticMeshComponent = struct {
    visable: bool = true,
    mesh: rendering_system.StaticMeshHandle,
    material: rendering_system.MaterialHandle,
    instance: ?rendering_system.SceneInstanceHandle = null,
};

// Components
pub const NodeComponents = struct {
    static_mesh: ?StaticMeshComponent = null,
    collider: ?void = null,
    light: ?void = null,
};

// Systems
pub const EntityUpdateData = struct { entity: *Entity, delta_time: f32 };
pub const EntityEventData = struct { world: *World, entity: *Entity };
pub const EntitySystems = struct {
    const Self = @This();

    pub fn frame_start(self: *Self, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("frame_start", EntityUpdateData, self.*, .{ .entity = entity, .delta_time = delta_time });
    }

    pub fn pre_physics(self: *Self, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("pre_physics", EntityUpdateData, self.*, .{ .entity = entity, .delta_time = delta_time });
    }

    pub fn post_physics(self: *Self, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("post_physics", EntityUpdateData, self.*, .{ .entity = entity, .delta_time = delta_time });
    }

    pub fn pre_render(self: *Self, entity: *Entity) void {
        callMethodOnFieldsIfExists("pre_render", *Entity, self.*, entity);
    }

    pub fn frame_end(self: *Self, entity: *Entity) void {
        callMethodOnFieldsIfExists("frame_end", *Entity, self.*, entity);
    }

    pub fn add_to_world(self: *Self, world: *World, entity: *Entity) void {
        callMethodOnFieldsIfExists("add_to_world", EntityEventData, self.*, .{ .world = world, .entity = entity });
    }

    pub fn remove_from_world(self: *Self, world: *World, entity: *Entity) void {
        callMethodOnFieldsIfExists("remove_from_world", EntityEventData, self.*, .{ .world = world, .entity = entity });
    }
};

pub const WorldUpdateData = struct { world: *World, delta_time: f32 };
pub const WorldSystems = struct {
    const Self = @This();

    rendering: ?WorldRenderingSystem = null,

    pub fn frame_start(self: *Self, world: *World, delta_time: f32) void {
        callMethodOnFieldsIfExists("frame_start", WorldUpdateData, self.*, .{ .world = world, .delta_time = delta_time });
    }

    pub fn pre_physics(self: *Self, world: *World, delta_time: f32) void {
        callMethodOnFieldsIfExists("pre_physics", WorldUpdateData, self.*, .{ .world = world, .delta_time = delta_time });
    }

    pub fn post_physics(self: *Self, world: *World, delta_time: f32) void {
        callMethodOnFieldsIfExists("post_physics", WorldUpdateData, self.*, .{ .world = world, .delta_time = delta_time });
    }

    pub fn pre_render(self: *Self, world: *World) void {
        callMethodOnFieldsIfExists("pre_render", *World, self.*, world);
    }

    pub fn frame_end(self: *Self, world: *World) void {
        callMethodOnFieldsIfExists("frame_end", *World, self.*, world);
    }

    pub fn add_to_world(self: *Self, world: *World, entity: *Entity) void {
        callMethodOnFieldsIfExists("add_to_world", EntityEventData, self.*, .{ .world = world, .entity = entity });
        entity.systems.add_to_world(world, entity);
    }

    pub fn remove_from_world(self: *Self, world: *World, entity: *Entity) void {
        entity.systems.remove_from_world(world, entity);
        callMethodOnFieldsIfExists("remove_from_world", EntityEventData, self.*, .{ .world = world, .entity = entity });
    }
};

// Handles
pub const NodeHandle = NodePool.Handle;
pub const EntityHandle = EntityPool.Handle;
pub const WorldHandle = WorldPool.Handle;

// Containers
pub const NodePool = StableObjectPool(Node);
pub const EntityPool = StableObjectPool(Entity);
pub const WorldPool = StableObjectPool(World);

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

    handle: EntityHandle,
    world_handle: ?WorldHandle = null,

    name: ?std.ArrayList(u8) = null,
    transform: Transform = .{},

    root_nodes: NodeList = .{},
    node_pool: NodePool,

    systems: EntitySystems = .{},

    pub fn init(allocator: std.mem.Allocator, systems: EntitySystems) !Self {
        return .{
            .handle = undefined,
            .node_pool = try NodePool.init(allocator),
            .systems = systems,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.name) |name| {
            name.deinit();
        }

        self.node_pool.deinit();
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
        self.node_pool.get(handle).?.handle = handle;

        if (parent) |parent_handle| {
            if (self.node_pool.get(parent_handle)) |parent_node| {
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
        var next_handle: ?NodeHandle = node_handle;
        var transform: ?Transform = null;

        while (next_handle) |handle| {
            const node = self.node_pool.get(handle).?;
            const parent_transform: Transform = transform orelse .{};
            transform = parent_transform.transform_by(&node.local_transform);
            next_handle = node.parent;
        }

        return transform;
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
};

// World
pub const World = struct {
    const Self = @This();

    handle: WorldHandle,
    entities: std.AutoArrayHashMap(EntityHandle, *Entity),
    systems: WorldSystems = .{},

    pub fn init(allocator: std.mem.Allocator, systems: WorldSystems) Self {
        return .{
            .handle = undefined,
            .entities = std.AutoArrayHashMap(EntityHandle, *Entity).init(allocator),
            .systems = systems,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) void {

        // Frame Start
        {
            //TODO: run in parallel
            for (self.entities.values()) |entity| {
                entity.systems.frame_start(entity, delta_time);
            }
            self.systems.frame_start(self, delta_time);
        }

        // Pre Physics
        {
            //TODO: run in parallel
            for (self.entities.values()) |entity| {
                entity.systems.pre_physics(entity, delta_time);
            }

            self.systems.pre_physics(self, delta_time);
        }

        //TODO: simulate physics here

        // Post Physics
        {
            //TODO: run in parallel
            for (self.entities.values()) |entity| {
                entity.systems.post_physics(entity, delta_time);
            }
            self.systems.post_physics(self, delta_time);
        }

        // Pre Render
        {
            //TODO: run in parallel
            for (self.entities.values()) |entity| {
                entity.systems.pre_render(entity);
            }
            self.systems.pre_render(self);
        }

        //TODO: Submit Render Here???????

        // Frame End
        {
            //TODO: run in parallel
            for (self.entities.values()) |entity| {
                entity.systems.frame_end(entity);
            }
            self.systems.frame_end(self);
        }
    }
};

// Universe
pub const Universe = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    entites: EntityPool,
    worlds: WorldPool,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .entites = try EntityPool.init(allocator),
            .worlds = try WorldPool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entites.deinit();
        self.worlds.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) void {
        var iter = self.worlds.iterator();
        while (iter.next()) |world| {
            world.update(delta_time);
        }
    }

    pub fn create_world(self: *Self, systems: WorldSystems) !WorldHandle {
        const handle = try self.worlds.insert(World.init(self.allocator, systems));
        self.worlds.get(handle).?.handle = handle;
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

    pub fn create_entity(self: *Self, systems: EntitySystems) !EntityHandle {
        const handle = try self.entites.insert(try Entity.init(self.allocator, systems));
        self.entites.get(handle).?.handle = handle;
        return handle;
    }

    pub fn destroy_entity(self: *Self, entity_handle: EntityHandle) void {
        if (self.entites.remove(entity_handle)) |entity| {
            entity.deinit();
            self.allocator.destroy(entity);
        }
    }

    pub fn add_to_world(self: *Self, world_handle: WorldHandle, entity_handle: EntityHandle) !void {
        if (self.worlds.get(world_handle)) |world| {
            if (self.entites.get(entity_handle)) |entity| {
                std.debug.assert(entity.world_handle == null);
                try world.entities.put(entity_handle, entity);
                world.systems.add_to_world(world, entity);
            }
        }
    }
};

pub const EntityRenderingSystem = struct {
    // const Self = @This();

    // scene: ?*rendering_system.Scene = null,

    // pub fn pre_render(self: *Self, entity: *Entity) void {
    //     if (self.scene) |scene| {
    //         var iter = entity.nodes.pool.iterator();
    //         while (iter.next()) |entry| {
    //             if (entry.value_ptr.components.static_mesh) |*static_mesh_component| {
    //                 const world_transform = entity.transform.transform_by(&entity.nodes.get_entity_transform(entry.handle).?);
    //                 if (static_mesh_component.instance) |instance| {
    //                     // Parallel updates won't cause race condition, only adding and removing can cause race conditions
    //                     scene.update_instance(instance, &world_transform);
    //                 }
    //             }
    //         }
    //     }
    // }
};

pub const WorldRenderingSystem = struct {
    const Self = @This();

    scene: rendering_system.Scene,

    pub fn frame_start(self: *Self, data: WorldUpdateData) void {
        _ = data; // autofix
        _ = self; // autofix
        //std.log.info("WorldRenderingSystem: frame_start", .{});
    }

    pub fn pre_render(self: *Self, world: *World) void {
        _ = self; // autofix
        _ = world; // autofix
        // var iter = world.entities.iterator();
        // while (iter.next_value()) |entity| {
        //     update_entity_instances(&self.scene, entity);
        // }
    }

    fn update_entity_instances(scene: *rendering_system.Scene, entity: *Entity) void {
        var iter = entity.node_pool.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.components.static_mesh) |*static_mesh_component| {
                const world_transform = entity.transform.transform_by(&entity.get_node_root_transform(entry.handle).?);
                if (static_mesh_component.instance) |instance| {
                    scene.update_instance(instance, &world_transform);
                } else {
                    static_mesh_component.instance = scene.add_instace(static_mesh_component.mesh, static_mesh_component.material, &world_transform) catch |err| {
                        std.log.info("Failed to add scene instance {}", .{err});
                        return;
                    };
                    std.log.info("Added mesh to scene: {}", .{static_mesh_component.instance.?});
                }
            }
        }
    }
};

fn callMethodOnFieldsIfExists(
    comptime method_name: []const u8,
    comptime Args: type,
    self: anytype,
    args: Args,
) void {
    inline for (std.meta.fields(@TypeOf(self))) |struct_field| {
        const field_type = unwrapOptionalType(struct_field.type) orelse @compileError("Field must be an optional type");

        if (comptime std.meta.hasMethod(field_type, method_name)) {
            var field_opt = @field(self, struct_field.name);

            if (field_opt) |*field| {
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
