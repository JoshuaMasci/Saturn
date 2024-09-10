const std = @import("std");
const za = @import("zalgebra");
const Transform = @import("unscaled_transform.zig");

const physics_system = @import("physics");
const rendering_system = @import("rendering.zig");

const World = @import("world2.zig").World;

pub const EntityPhysics = struct {
    shape: physics_system.Shape,
    sensor: bool,
};

pub const EntityRendering = struct {
    mesh: rendering_system.StaticMeshHandle,
    material: rendering_system.MaterialHandle,
};

pub const StaticEntity = struct {
    const Self = @This();

    transform: Transform = .{},
    physics: ?EntityPhysics = null,
    mesh: ?EntityRendering = null,

    body: ?physics_system.BodyHandle = null,
    instance: ?rendering_system.SceneInstanceHandle = null,

    pub fn add_to_world(self: *Self, world: *World) !void {
        if (self.physics) |body| {
            self.body = world.physics_world.add_body(&.{
                .shape = body.shape,
                .position = self.transform.position.toArray(),
                .rotation = self.transform.rotation.toArray(),
                .object_layer = if (body.sensor) 3 else 2,
                .motion_type = .static,
                .is_sensor = body.sensor,
                .friction = 0.2,
                .linear_damping = 0.0,
            });
        }

        if (self.mesh) |mesh| {
            self.instance = try world.rendering_world.add_instace(mesh.mesh, mesh.material, &self.transform.to_scaled(za.Vec3.ONE));
        }
    }

    pub fn remove_from_world(self: *Self, world: *World) void {
        if (self.body) |body_handle| {
            world.physics_world.remove_body(body_handle);
            self.body = null;
        }

        if (self.instance) |instance_handle| {
            world.rendering_world.remove_instance(instance_handle);
            self.instance = null;
        }
    }
};

pub const DynamicEntity = struct {
    const Self = @This();

    transform: Transform,
    linear_velocity: za.Vec3,
    angular_velocity: za.Vec3,
    physics: ?EntityPhysics = null,
    mesh: ?EntityRendering = null,

    body: ?physics_system.BodyHandle,
    instance: ?rendering_system.SceneInstanceHandle,

    pub fn add_to_world(self: *Self, world: *World) !void {
        if (self.physics) |body| {
            self.body = self.physics_world.add_body(&.{
                .shape = body.shape,
                .position = self.transform.position.toArray(),
                .rotation = self.transform.rotation.toArray(),
                .object_layer = if (!body.sensor) 1 else 3,
                .motion_type = .Dynamic,
                .is_sensor = body.sensor,
                .friction = 0.2,
                .linear_damping = 0.0,
            });
        }

        if (self.mesh) |mesh| {
            self.instance = try world.rendering_world.add_instace(mesh.mesh, mesh.material, &self.transform.to_scaled(za.Vec3.ONE));
        }
    }

    pub fn remove_from_world(self: *Self, world: *World) void {
        if (self.body) |body_handle| {
            world.physics_world.remove_body(body_handle);
            self.body = null;
        }

        if (self.instance) |instance_handle| {
            world.rendering_world.remove_instance(instance_handle);
            self.instance = null;
        }
    }

    pub fn pre_physics_update(self: *Self, world: *World) void {
        if (self.body) |body_handle| {
            world.physics_world.set_body_transform(body_handle, &.{
                .position = self.transform.position.toArray(),
                .rotation = self.transform.rotation.toArray(),
            });
            world.physics_world.set_body_linear_velocity(body_handle, self.linear_velocity.toArray());
            world.physics_world.set_body_angular_velocity(body_handle, self.angular_velocity.toArray());
        }
    }

    pub fn post_physics_update(self: *Self, world: *World) void {
        if (self.body) |body_handle| {
            const body_transform = world.physics_world.get_body_transform(body_handle);
            self.transform.position = za.Vec3.fromArray(body_transform.position);
            self.transform.rotation = za.Quat.fromArray(body_transform.rotation);
            self.linear_velocity = za.Vec3.fromArray(world.physics_world.get_body_linear_velocity(body_handle));
            self.angular_velocity = za.Vec3.fromArray(world.physics_world.get_body_angular_velocity(body_handle));
        }

        if (self.instance) |instance_handle| {
            world.rendering_world.update_instance(instance_handle, &self.transform.to_scaled(za.Vec3.ONE));
        }
    }
};
