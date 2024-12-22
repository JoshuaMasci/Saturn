const std = @import("std");
const za = @import("zalgebra");
const Transform = @import("transform.zig");
const ObjectPool = @import("object_pool.zig").HandlePool;
const PerspectiveCamera = @import("camera.zig").PerspectiveCamera;

const asset = @import("asset.zig");
const rendering_scene = @import("rendering/scene.zig");

pub const DebugCameraEntitySystem = struct {
    const Self = @This();
    const input = @import("input.zig");

    linear_speed: za.Vec3 = za.Vec3.set(5.0),
    angular_speed: za.Vec3 = za.Vec3.set(std.math.pi),

    pitch_yaw: za.Vec2 = za.Vec2.ZERO,
    linear_input: za.Vec3 = za.Vec3.ZERO,
    angular_input: za.Vec3 = za.Vec3.ZERO,

    camera_node: ?NodeHandle = null,

    cast_ray: bool = false,

    pub fn pre_physics(self: *Self, data: EntityUpdateData) void {
        const linear_speed = data.entity.transform.rotation.rotateVec(self.linear_input.mul(self.linear_speed));
        if (data.entity.systems.physics) |*entity_physics| {
            entity_physics.linear_velocity = linear_speed;
            entity_physics.angular_velocity = za.Vec3.ZERO;
        } else {
            data.entity.transform.position = data.entity.transform.position.add(linear_speed.scale(data.delta_time));
        }

        const angular_rotation = self.angular_input.mul(self.angular_speed).scale(data.delta_time);

        self.pitch_yaw = self.pitch_yaw.add(angular_rotation.toVec2());

        // Clamp pitch and keep roation between 0->360 degrees
        const pi_half = std.math.pi / 2.0;
        const pi_2 = std.math.pi * 2.0;
        self.pitch_yaw = za.Vec2.new(std.math.clamp(self.pitch_yaw.x(), -pi_half, pi_half), @mod(self.pitch_yaw.y(), pi_2));

        const pitch_quat = za.Quat.fromAxis(self.pitch_yaw.x(), za.Vec3.X);
        const yaw_quat = za.Quat.fromAxis(self.pitch_yaw.y(), za.Vec3.Y);
        data.entity.transform.rotation = yaw_quat.mul(pitch_quat).norm();

        // Axis events should fire each frame they are active, so the input is reset each update
        self.angular_input = za.Vec3.set(0.0);

        if (self.cast_ray) {
            self.cast_ray = false;
        }
    }

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        if (event.button == .player_interact and event.state == .pressed) {
            self.cast_ray = true;
        }
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        switch (event.axis) {
            .player_move_left_right => self.linear_input.data[0] = event.get_value(true),
            .player_move_up_down => self.linear_input.data[1] = event.get_value(true),
            .player_move_forward_backward => self.linear_input.data[2] = event.get_value(true),

            .player_rotate_pitch => self.angular_input.data[0] = event.get_value(false),
            .player_rotate_yaw => self.angular_input.data[1] = event.get_value(false),

            //else => {},
        }
    }
};

const rendering_system = @import("rendering.zig");
pub const StaticMeshComponent = struct {
    visable: bool = true,
    mesh: rendering_system.StaticMeshHandle,
    material: rendering_system.MaterialHandle,
    instance: ?rendering_system.SceneInstanceHandle = null,
};
pub const RenderEntitySystem = struct {};
pub const RenderWorldSystem = struct {
    const Self = @This();

    scene: rendering_system.Scene,

    pub fn init(rendering_backend: *rendering_system.Backend) Self {
        return .{
            .scene = rendering_backend.create_scene(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.scene.deinit();
    }

    pub fn register_entity(self: *Self, data: EntityRegisterData) void {
        if (data.entity.systems.render) |render_system| {
            _ = render_system; // autofix
            var iter = data.entity.node_pool.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.components.static_mesh) |*static_mesh_component| {
                    const world_transform = data.entity.get_node_world_transform(entry.handle).?;
                    const instance = self.scene.add_instace(static_mesh_component.mesh, static_mesh_component.material, &world_transform) catch std.debug.panic("Failed to add instance to scene", .{});
                    static_mesh_component.instance = instance; //TODO: store instance in entity render system
                }
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

const physics = @import("physics");
pub const PhysicsColliderComponent = struct {
    shape: physics.Shape,
};

pub const PhysicsEntitySystem = struct {
    motion_type: physics.MotionType = .static,
    object_layer: u16 = 1,
    compund_shape: ?physics.Shape = null,
    body_handle: ?physics.BodyHandle = null,

    linear_velocity: za.Vec3 = za.Vec3.ZERO,
    angular_velocity: za.Vec3 = za.Vec3.ZERO,
};
pub const PhysicsWorldSystem = struct {
    const Self = @This();

    physics_world: physics.World,

    pub fn init() Self {
        return .{
            .physics_world = physics.World.init(.{
                .max_bodies = 65536,
                .max_body_pairs = 65536,
                .max_contact_constraints = 65536,
                .temp_allocation_size = 1024 * 1024 * 16, //16mb
            }),
        };
    }

    pub fn deinit(self: *Self) void {
        self.physics_world.deinit();
    }

    pub fn register_entity(self: *Self, data: EntityRegisterData) void {
        if (data.entity.systems.physics) |*entity_physics| {
            var compound_shape = physics.Shape.init_compound_shape();
            var iter = data.entity.node_pool.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.components.collider) |collider| {
                    const child_transform = data.entity.get_node_root_transform(entry.handle).?;
                    _ = compound_shape.add_child_shape(&.{
                        .position = child_transform.position.toArray(),
                        .rotation = child_transform.rotation.toArray(),
                    }, collider.shape, 0);
                }
            }

            entity_physics.compund_shape = compound_shape;
            entity_physics.body_handle = self.physics_world.add_body(&.{
                .shape = compound_shape,
                .position = data.entity.transform.position.toArray(),
                .rotation = data.entity.transform.rotation.toArray(),
                .linear_velocity = entity_physics.linear_velocity.toArray(),
                .angular_velocity = entity_physics.angular_velocity.toArray(),
                .user_data = @intCast(data.entity.handle),
                .object_layer = entity_physics.object_layer,
                .motion_type = entity_physics.motion_type,
                .is_sensor = false,
                .friction = 0.2,
                .linear_damping = 0.0,
            });
        }
    }

    pub fn pre_physics(self: *Self, data: WorldUpdateData) void {
        for (data.world.entities.values()) |entity| {
            if (entity.systems.physics) |entity_physics| {
                if (entity_physics.body_handle) |body_handle| {
                    self.physics_world.set_body_transform(body_handle, &.{ .position = entity.transform.position.toArray(), .rotation = entity.transform.rotation.toArray() });
                    self.physics_world.set_body_linear_velocity(body_handle, entity_physics.linear_velocity.toArray());
                    self.physics_world.set_body_angular_velocity(body_handle, entity_physics.angular_velocity.toArray());
                }
            }
        }
    }

    pub fn simulate_physics(self: *Self, data: WorldUpdateData) void {
        self.physics_world.update(data.delta_time, 1);
    }

    pub fn post_physics(self: *Self, data: WorldUpdateData) void {
        for (data.world.entities.values()) |*entity| {
            if (entity.systems.physics) |*entity_physics| {
                if (entity_physics.body_handle) |body_handle| {
                    const body_transform = self.physics_world.get_body_transform(body_handle);
                    entity.transform.position = za.Vec3.fromArray(body_transform.position);
                    entity.transform.rotation = za.Quat.fromArray(body_transform.rotation);
                    entity_physics.linear_velocity = za.Vec3.fromArray(self.physics_world.get_body_linear_velocity(body_handle));
                    entity_physics.angular_velocity = za.Vec3.fromArray(self.physics_world.get_body_angular_velocity(body_handle));
                }
            }
        }
    }
};

// Components
pub const NodeComponents = struct {
    static_mesh: ?StaticMeshComponent = null,
    static_mesh2: ?rendering_scene.StaticMeshComponent = null,
    camera: ?PerspectiveCamera = null,
    collider: ?PhysicsColliderComponent = null,
};

// Systems
pub const EntityUpdateData = struct { world: *const World, entity: *Entity, delta_time: f32 };
pub const EntityEventData = struct { world: *World, entity: *Entity };
pub const EntitySystems = struct {
    const Self = @This();

    render: ?RenderEntitySystem = null,
    physics: ?PhysicsEntitySystem = null,
    debug_camera: ?DebugCameraEntitySystem = null,

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn frame_start(self: *Self, world: *const World, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("frame_start", EntityUpdateData, self, .{ .world = world, .entity = entity, .delta_time = delta_time });
    }

    pub fn pre_physics(self: *Self, world: *const World, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("pre_physics", EntityUpdateData, self, .{ .world = world, .entity = entity, .delta_time = delta_time });
    }

    pub fn post_physics(self: *Self, world: *const World, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("post_physics", EntityUpdateData, self, .{ .world = world, .entity = entity, .delta_time = delta_time });
    }

    pub fn pre_render(self: *Self, world: *const World, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("pre_render", EntityUpdateData, self, .{ .world = world, .entity = entity, .delta_time = delta_time });
    }

    pub fn frame_end(self: *Self, world: *const World, entity: *Entity, delta_time: f32) void {
        callMethodOnFieldsIfExists("frame_end", EntityUpdateData, self, .{ .world = world, .entity = entity, .delta_time = delta_time });
    }
};

pub const WorldUpdateData = struct { world: *World, delta_time: f32 };
pub const EntityRegisterData = struct { world: *World, entity: *Entity };
pub const WorldSystems = struct {
    const Self = @This();

    render: ?RenderWorldSystem = null,
    physics: ?PhysicsWorldSystem = null,

    pub fn deinit(self: *Self) void {
        if (self.render) |*render| {
            render.deinit();
        }

        if (self.physics) |*physics_system| {
            physics_system.deinit();
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

    pub fn simulate_physics(self: *Self, world: *World, delta_time: f32) void {
        callMethodOnFieldsIfExists("simulate_physics", WorldUpdateData, self, .{ .world = world, .delta_time = delta_time });
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

// Nodes
pub const Node = struct {
    const Self = @This();

    handle: NodeHandle,

    local_transform: Transform,
    components: NodeComponents,

    parent: ?NodeHandle = null,
    childen: NodeList = .{},
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

// Entity
pub const Entity = struct {
    const Self = @This();

    pub const Handle = u64;
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
            .handle = next_handle.fetchAdd(1, .monotonic), //TODO: is this the correct atomic order?,
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

    pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
        switch (stage) {
            .frame_start => {
                //TODO: run in parallel
                for (self.entities.values()) |*entity| {
                    entity.systems.frame_start(self, entity, delta_time);
                }
                self.systems.frame_start(self, delta_time);
            },
            .pre_physics => {
                for (self.entities.values()) |*entity| {
                    entity.systems.pre_physics(self, entity, delta_time);
                }

                self.systems.pre_physics(self, delta_time);
            },
            .physics => {
                self.systems.simulate_physics(self, delta_time);
            },
            .post_physics => {
                for (self.entities.values()) |*entity| {
                    entity.systems.post_physics(self, entity, delta_time);
                }
                self.systems.post_physics(self, delta_time);
            },
            .pre_render => {
                for (self.entities.values()) |*entity| {
                    entity.systems.pre_render(self, entity, delta_time);
                }
                self.systems.pre_render(self);
            },
            .frame_end => {
                for (self.entities.values()) |*entity| {
                    entity.systems.frame_end(self, entity, delta_time);
                }
                self.systems.frame_end(self);
            },
        }
    }

    pub fn add_entity(self: *Self, entity: Entity) Entity.Handle {
        self.entities.put(entity.handle, entity) catch std.debug.panic("Failed to push entity to entity list", .{});
        self.systems.register_entity(self, self.entities.getPtr(entity.handle).?);
        return entity.handle;
    }
};

pub const UpdateStage = enum {
    frame_start,
    pre_physics,
    physics,
    post_physics,
    pre_render,
    frame_end,
};

// Universe
pub const Universe = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    worlds: std.AutoHashMap(World.Handle, *World),

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .worlds = std.AutoHashMap(World.Handle, *World).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.worlds.valueIterator();
        while (iter.next()) |world| {
            world.*.deinit();
        }
        self.worlds.deinit();
    }

    pub fn update(self: *Self, stage: UpdateStage, delta_time: f32) void {
        var iter = self.worlds.valueIterator();
        while (iter.next()) |world| {
            world.*.update(stage, delta_time);
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
            return entry.value;
        }
        return null;
    }
};

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
