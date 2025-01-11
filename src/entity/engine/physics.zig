const za = @import("zalgebra");
const Transform = @import("../../transform.zig");

const Entity = @import("../entity.zig");
const World = @import("../world.zig");
const UpdateStage = @import("../universe.zig").UpdateStage;

const physics = @import("physics");

pub const RayCastHit = struct {
    entity_handle: Entity.Handle,
    shape_index: u32 = 0,
    distance: f32,
    ws_position: za.Vec3,
    ws_normal: za.Vec3,

    fn init(hit: physics.RayCastHit) @This() {
        return .{
            .entity_handle = @intCast(hit.body_user_data),
            .shape_index = hit.shape_index,
            .distance = hit.distance,
            .ws_position = za.Vec3.fromArray(hit.ws_position),
            .ws_normal = za.Vec3.fromArray(hit.ws_normal),
        };
    }
};

pub const PhysicsColliderComponent = struct {
    shape: physics.Shape,
};

pub const PhysicsEntitySystem = struct {
    const Self = @This();

    motion_type: physics.MotionType = .static,
    object_layer: u16 = 1,
    compund_shape: ?physics.Shape = null,
    body_handle: ?physics.BodyHandle = null,

    linear_velocity: za.Vec3 = za.Vec3.ZERO,
    angular_velocity: za.Vec3 = za.Vec3.ZERO,

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
    }

    pub fn update(self: *Self, data: Entity.UpdateData) void {
        _ = self; // autofix
        _ = data; // autofix
    }
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

    pub fn registerEntity(self: *Self, data: World.EntityRegisterData) void {
        if (data.entity.systems.physics) |*entity_physics| {
            var compound_shape = physics.Shape.init_compound_shape();
            var iter = data.entity.nodes.pool.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.components.collider) |collider| {
                    const child_transform = data.entity.nodes.getNodeRootTransform(entry.handle).?;
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

    pub fn update(self: *Self, data: World.UpdateData) void {
        switch (data.stage) {
            .pre_physics => self.prePhysics(data),
            .physics => self.simulatephysics(data),
            .post_physics => self.postphysics(data),
            else => {},
        }
    }

    pub fn prePhysics(self: *Self, data: World.UpdateData) void {
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

    pub fn simulatephysics(self: *Self, data: World.UpdateData) void {
        self.physics_world.update(data.delta_time, 1);
    }

    pub fn postphysics(self: *Self, data: World.UpdateData) void {
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

    pub fn castRay(self: Self, object_layer: u16, start: za.Vec3, direction: za.Vec3) ?RayCastHit {
        if (self.physics_world.ray_cast_closest(object_layer, start.toArray(), direction.toArray())) |hit| {
            return RayCastHit.init(hit);
        }
        return null;
    }

    pub fn castRayIgnoreEntity(self: Self, object_layer: u16, ignore: *Entity, start: za.Vec3, direction: za.Vec3) ?RayCastHit {
        //TODO: this should log error rather than crash?
        const ignore_body = ignore.systems.physics.?.body_handle.?;
        if (self.physics_world.ray_cast_closest_ignore(object_layer, ignore_body, start.toArray(), direction.toArray())) |hit| {
            return RayCastHit.init(hit);
        }
        return null;
    }
};
