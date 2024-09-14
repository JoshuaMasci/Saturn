const std = @import("std");
const za = @import("zalgebra");
const Transform = @import("unscaled_transform.zig");

const physics_system = @import("physics");
const rendering_system = @import("rendering.zig");

const world_zig = @import("world.zig");
const EntityHandle = world_zig.EntityHandle;
const World = world_zig.World;

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
    handle: ?EntityHandle = null,

    transform: Transform = .{},
    physics: ?EntityPhysics = null,
    mesh: ?EntityRendering = null,

    body: ?physics_system.BodyHandle = null,
    instance: ?rendering_system.SceneInstanceHandle = null,

    pub fn add_to_world(self: *Self, handle: EntityHandle, world: *World) !void {
        self.handle = handle;

        if (self.physics) |body| {
            self.body = world.physics_world.add_body(&.{
                .shape = body.shape,
                .position = self.transform.position.toArray(),
                .rotation = self.transform.rotation.toArray(),
                .user_data = self.handle.?.to_u64(),
                .object_layer = if (body.sensor) 2 else 3,
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

        self.handle = null;
    }
};

pub const DynamicEntity = struct {
    const Self = @This();
    handle: ?EntityHandle = null,

    transform: Transform = .{},
    linear_velocity: za.Vec3 = za.Vec3.ZERO,
    angular_velocity: za.Vec3 = za.Vec3.ZERO,
    physics: ?EntityPhysics = null,
    mesh: ?EntityRendering = null,

    body: ?physics_system.BodyHandle = null,
    instance: ?rendering_system.SceneInstanceHandle = null,

    pub fn add_to_world(self: *Self, handle: EntityHandle, world: *World) !void {
        self.handle = handle;

        if (self.physics) |body| {
            self.body = world.physics_world.add_body(&.{
                .shape = body.shape,
                .position = self.transform.position.toArray(),
                .rotation = self.transform.rotation.toArray(),
                .user_data = self.handle.?.to_u64(),
                .object_layer = if (body.sensor) 2 else 3,
                .motion_type = .dynamic,
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

        self.handle = null;
    }

    pub fn pre_physics_update(self: *Self, world: *World, delta_time: f32) void {
        _ = delta_time; // autofix
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

pub const Character = struct {
    const Self = @This();
    handle: ?EntityHandle = null,

    transform: Transform = .{},
    linear_velocity: za.Vec3 = za.Vec3.ZERO,

    mesh: ?EntityRendering = null,
    physics_shape: physics_system.Shape,

    //Camera State
    camera_offset: za.Vec3 = za.Vec3.Z,
    camera_pitch: f32 = 0.0,

    //Input
    linear_input: za.Vec2 = za.Vec2.ZERO,
    angular_input: za.Vec2 = za.Vec2.ZERO,
    jump_input: bool = false,
    jump_count: u32 = 0,

    //Ground Constants
    ground_velocity: za.Vec2 = za.Vec2.set(5.0),
    air_acceleration: za.Vec2 = za.Vec2.set(1.0),
    angular_speed: za.Vec2 = za.Vec2.set(std.math.pi),
    jump_velocity: f32 = 10.0,
    max_jumps: u32 = 1,

    physics: ?physics_system.CharacterHandle = null,
    instance: ?rendering_system.SceneInstanceHandle = null,

    pub fn add_to_world(self: *Self, handle: EntityHandle, world: *World) !void {
        self.handle = handle;

        self.physics =
            world.physics_world.add_character(self.physics_shape, &.{
            .position = self.transform.position.toArray(),
            .rotation = self.transform.rotation.toArray(),
        }, null);

        if (self.mesh) |mesh| {
            self.instance = try world.rendering_world.add_instace(mesh.mesh, mesh.material, &self.transform.to_scaled(za.Vec3.ONE));
        }
    }

    pub fn remove_from_world(self: *Self, world: *World) void {
        if (self.physics) |physics_handle| {
            world.physics_world.remove_character(physics_handle);
            self.physics = null;
        }

        if (self.instance) |instance_handle| {
            world.rendering_world.remove_instance(instance_handle);
            self.instance = null;
        }

        self.handle = null;
    }

    pub fn pre_physics_update(self: *Self, world: *World, delta_time: f32) void {
        if (self.physics) |physics_handle| {
            {
                const angular_movement = self.angular_input.mul(self.angular_speed).scale(delta_time);
                const up_axis = self.transform.get_up();
                const yaw_rotation = za.Quat.fromAxis(angular_movement.x(), up_axis);
                self.transform.rotation = yaw_rotation.mul(self.transform.rotation).norm();
                const pi_half = std.math.pi / 2.0;
                self.camera_pitch = std.math.clamp(self.camera_pitch + angular_movement.y(), -pi_half, pi_half);
                world.physics_world.set_character_rotation(physics_handle, self.transform.rotation.toArray());
            }

            const ground_state = world.physics_world.get_character_ground_state(physics_handle);
            if (ground_state == .OnGround) {
                // If player is on ground
                var velocity = za.Vec3.fromArray(world.physics_world.get_character_ground_velocity(physics_handle));
                const input_velocity = self.linear_input.norm().mul(self.ground_velocity);
                const input_velocity_ws = self.transform.rotation.rotateVec(za.Vec3.new(input_velocity.x(), 0.0, input_velocity.y()));
                velocity = velocity.add(input_velocity_ws);

                if (self.jump_input) {
                    velocity = velocity.add(self.transform.get_up().scale(self.jump_velocity));
                }

                self.linear_velocity = velocity;
            } else {
                // If player is in the air
                var velocity = self.linear_velocity;
                const input_acceleration = self.linear_input.norm().mul(self.air_acceleration).scale(delta_time);
                const input_acceleration_ws = self.transform.rotation.rotateVec(za.Vec3.new(input_acceleration.x(), 0.0, input_acceleration.y()));
                velocity = velocity.add(input_acceleration_ws);
                self.linear_velocity = velocity;
            }

            world.physics_world.set_character_linear_velocity(physics_handle, self.linear_velocity.toArray());
        }

        //TODO: fix input system so I don't have to reset both these here
        self.jump_input = false;
        self.angular_input = za.Vec2.set(0.0);
    }

    pub fn post_physics_update(self: *Self, world: *World) void {
        if (self.physics) |physics_handle| {
            const body_transform = world.physics_world.get_character_transform(physics_handle);
            self.transform.position = za.Vec3.fromArray(body_transform.position);
            self.transform.rotation = za.Quat.fromArray(body_transform.rotation);
            self.linear_velocity = za.Vec3.fromArray(world.physics_world.get_character_linear_velocity(physics_handle));
        }

        if (self.instance) |instance_handle| {
            world.rendering_world.update_instance(instance_handle, &self.transform.to_scaled(za.Vec3.ONE));
        }
    }

    pub fn get_camera_transform(self: Self) Transform {
        const pitch_quat = za.Quat.fromAxis(self.camera_pitch, za.Vec3.X);

        return .{
            .position = self.transform.position,
            .rotation = self.transform.rotation.mul(pitch_quat),
        };
    }

    const input_system = @import("input.zig");
    pub fn on_button_event(self: *Self, event: input_system.ButtonEvent) void {
        switch (event.button) {
            .player_move_jump => {
                self.jump_input = event.state == .pressed;
            },
            else => {},
        }
    }

    pub fn on_axis_event(self: *Self, event: input_system.AxisEvent) void {
        switch (event.axis) {
            .player_move_left_right => self.linear_input.data[0] = event.get_value(true),
            .player_move_forward_backward => self.linear_input.data[1] = event.get_value(true),

            .player_rotate_yaw => self.angular_input.data[0] = event.get_value(false),
            .player_rotate_pitch => self.angular_input.data[1] = event.get_value(false),

            else => {},
        }
    }
};
