const std = @import("std");
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

    body: physics.Body,

    linear_velocity: za.Vec3 = za.Vec3.ZERO,
    angular_velocity: za.Vec3 = za.Vec3.ZERO,

    pub fn init(motion_type: physics.MotionType) Self {
        return .{
            .body = physics.Body.init(.{
                .motion_type = motion_type,
                .object_layer = 1,
            }),
        };
    }

    pub fn deinit(self: *Self) void {
        self.body.deinit();
    }

    pub fn update(self: *Self, data: Entity.UpdateData) void {
        if (data.stage == .pre_physics) {
            self.body.setTransform(&.{
                .position = data.entity.transform.position.toArray(),
                .rotation = data.entity.transform.rotation.norm().toArray(),
            });
            self.body.setVelocity(&.{
                .linear = self.linear_velocity.toArray(),
                .angular = self.angular_velocity.toArray(),
            });
        } else if (data.stage == .post_physics) {
            const transform = self.body.getTransform();
            data.entity.transform.position = za.Vec3.fromArray(transform.position);
            data.entity.transform.rotation = za.Quat.fromArray(transform.rotation).norm();

            const velocity = self.body.getVelocity();
            self.linear_velocity = za.Vec3.fromArray(velocity.linear);
            self.angular_velocity = za.Vec3.fromArray(velocity.angular);
        }
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
            self.physics_world.addBody(entity_physics.body);
        }
    }

    pub fn update(self: *Self, data: World.UpdateData) void {
        switch (data.stage) {
            .physics => self.simulatephysics(data),
            else => {},
        }
    }

    pub fn simulatephysics(self: *Self, data: World.UpdateData) void {
        self.physics_world.update(data.delta_time, 1);
    }

    pub fn castRay(self: Self, object_layer: u16, start: za.Vec3, direction: za.Vec3) ?RayCastHit {
        _ = self; // autofix
        _ = object_layer; // autofix
        _ = start; // autofix
        _ = direction; // autofix
        // if (self.physics_world.ray_cast_closest(object_layer, start.toArray(), direction.toArray())) |hit| {
        //     return RayCastHit.init(hit);
        // }
        return null;
    }

    pub fn castRayIgnoreEntity(self: Self, object_layer: u16, ignore: *Entity, start: za.Vec3, direction: za.Vec3) ?RayCastHit {
        _ = self; // autofix
        _ = object_layer; // autofix
        _ = ignore; // autofix
        _ = start; // autofix
        _ = direction; // autofix
        //TODO: this should log error rather than crash?
        // const ignore_body = ignore.systems.physics.?.body_handle.?;
        // if (self.physics_world.ray_cast_closest_ignore(object_layer, ignore_body, start.toArray(), direction.toArray())) |hit| {
        //     return RayCastHit.init(hit);
        // }
        return null;
    }
};
