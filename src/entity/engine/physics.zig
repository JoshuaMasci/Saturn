const std = @import("std");
const zm = @import("zmath");
const Transform = @import("../../transform.zig");

const Entity = @import("../entity.zig");
const World = @import("../world.zig");
const UpdateStage = @import("../universe.zig").UpdateStage;

const WorldSystem = @import("../world_system.zig");

const physics = @import("physics");

pub const RayCastHit = struct {
    root_handle: Entity.Handle,
    entity_handle: Entity.Handle,
    distance: f32,
    ws_position: zm.Vec,
    ws_normal: zm.Vec,

    fn init(hit: physics.RayCastHit) @This() {
        return .{
            .root_handle = @intCast(hit.body_user_data),
            .entity_handle = @intCast(hit.shape_user_data),
            .distance = hit.distance,
            .ws_position = zm.loadArr3(hit.ws_position),
            .ws_normal = zm.loadArr3(hit.ws_normal),
        };
    }
};

pub const PhysicsColliderComponent = struct {
    shape: physics.Shape,
};

pub const PhysicsEntitySystem = struct {
    const Self = @This();

    body: physics.Body,

    linear_velocity: zm.Vec = zm.splat(zm.Vec, 0.0),
    angular_velocity: zm.Vec = zm.splat(zm.Vec, 0.0),

    pub fn init(entity_handle: Entity.Handle, motion_type: physics.MotionType) Self {
        return .{
            .body = physics.Body.init(.{
                .motion_type = motion_type,
                .user_data = @intCast(entity_handle),
                .object_layer = 1,
            }),
        };
    }

    pub fn deinit(self: *Self) void {
        self.body.deinit();
    }

    pub fn rebuildShape(self: *Self, entity: *Entity) void {
        self.body.removeAllShapes();
        addShapes(&self.body, entity);
        self.body.commitShapeChanges();
    }

    fn addShapes(body: *physics.Body, entity: *Entity) void {
        if (entity.systems.get(PhysicsColliderComponent)) |collider| {
            const root_transform = entity.getRootTransform();
            _ = body.addShape(
                collider.shape,
                zm.vecToArr3(root_transform.position),
                zm.vecToArr4(root_transform.rotation),
                entity.handle,
            );
        }

        for (entity.children.values()) |child| {
            addShapes(body, child);
        }
    }

    pub fn updateParallel(self: *Self, stage: UpdateStage, entity: *Entity, delta_time: f32) void {
        _ = delta_time; // autofix
        if (stage == .pre_physics) {
            self.body.setTransform(&.{
                .position = zm.vecToArr3(entity.transform.position),
                .rotation = zm.vecToArr4(zm.normalize4(entity.transform.rotation)),
            });
            self.body.setVelocity(&.{
                .linear = zm.vecToArr3(self.linear_velocity),
                .angular = zm.vecToArr3(self.angular_velocity),
            });
        } else if (stage == .post_physics) {
            const transform = self.body.getTransform();
            entity.transform.position = zm.loadArr3(transform.position);
            entity.transform.rotation = zm.normalize4(zm.loadArr4(transform.rotation));

            const velocity = self.body.getVelocity();
            self.linear_velocity = zm.loadArr3(velocity.linear);
            self.angular_velocity = zm.loadArr3(velocity.angular);
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

    pub fn registerEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix
        if (entity.systems.get(PhysicsEntitySystem)) |entity_physics| {
            self.physics_world.addBody(entity_physics.body);
        }
    }

    pub fn deregisterEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix
        if (entity.systems.get(PhysicsEntitySystem)) |entity_physics| {
            self.physics_world.removeBody(entity_physics.body);
        }
    }

    pub fn update(self: *Self, stage: UpdateStage, world: *World, delta_time: f32) void {
        _ = world; // autofix
        switch (stage) {
            .physics => self.simulatephysics(delta_time),
            else => {},
        }
    }

    pub fn simulatephysics(self: *Self, delta_time: f32) void {
        self.physics_world.update(delta_time, 1);
    }

    pub fn castRay(self: Self, object_layer: u16, start: zm.Vec, direction: zm.Vec) ?RayCastHit {
        if (self.physics_world.ray_cast_closest(object_layer, zm.vecToArr3(start), zm.vecToArr3(direction))) |hit| {
            return RayCastHit.init(hit);
        }
        return null;
    }

    pub fn castRayIgnoreEntity(self: Self, object_layer: u16, ignore: *Entity, start: zm.Vec, direction: zm.Vec) ?RayCastHit {
        //TODO: this should log error rather than crash?
        const ignore_body = ignore.root.systems.get(PhysicsEntitySystem).?.body;
        const start_a = zm.vecToArr3(start);
        const direction_a = zm.vecToArr3(direction);

        if (self.physics_world.castRayClosestIgnoreBody(object_layer, ignore_body, start_a, direction_a)) |hit| {
            return RayCastHit.init(hit);
        }
        return null;
    }

    pub fn castShape(self: Self, temp_allocator: std.mem.Allocator, object_layer: u16, shape: physics.Shape, transform: Transform) std.ArrayList(Entity.Handle) {
        var callback_list = ShapeCastHitList.init(temp_allocator);
        self.physics_world.castShape(object_layer, shape, &.{ .position = zm.vecToArr3(transform.position), .rotation = zm.vecToArr4(transform.rotation) }, &shapeCastCallback, &callback_list);
        return callback_list;
    }
};

pub const ShapeCastHitList = std.ArrayList(Entity.Handle);
fn shapeCastCallback(ptr_opt: ?*anyopaque, hit: physics.ShapeCastHit) callconv(.C) void {
    if (ptr_opt) |ptr| {
        const callback_list: *ShapeCastHitList = @alignCast(@ptrCast(ptr));
        callback_list.append(@intCast(hit.shape_user_data)) catch |err| {
            std.log.err("Failed to append shape cast hit {}", .{err});
        };
    }
}
