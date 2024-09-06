const std = @import("std");
const za = @import("zalgebra");

const ObjectPool = @import("object_pool.zig").ObjectPool;
const Transform = @import("transform.zig");

const physics_system = @import("physics");
const rendering_system = @import("rendering.zig");

const input_system = @import("input.zig");

const EntityPool = ObjectPool(u16, Entity);
pub const EntityHandle = EntityPool.Handle;
pub const Entity = struct {
    transform: Transform,
    body: ?physics_system.BodyHandle,
    instance: ?rendering_system.SceneInstanceHandle,
};

const CharacterPool = ObjectPool(u16, Character);
pub const CharacterHandle = CharacterPool.Handle;
pub const Character = struct {
    const Self = @This();

    //TODO: 3D movement state

    ground_velocity: za.Vec2 = za.Vec2.set(5.0),
    air_acceleration: za.Vec2 = za.Vec2.set(1.0),

    angular_speed: za.Vec2 = za.Vec2.set(std.math.pi),

    jump_velocity: f32 = 10.0,
    max_jumps: u32 = 1,

    linear_input: za.Vec2 = za.Vec2.ZERO,
    angular_input: za.Vec2 = za.Vec2.ZERO,

    jump_input: bool = false,
    jump_count: u32 = 0,

    //Camera State
    camera_offset: za.Vec3 = za.Vec3.Z,
    camera_pitch: f32 = 0.0,

    transform: Transform,
    render_object: ?rendering_system.SceneInstanceHandle,
    physics_character: ?physics_system.CharacterHandle,

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

    pub fn update(self: *Self, world: *World, delta_time: f32) void {
        if (self.physics_character) |physics_character_handle| {
            const body_transform = world.physics_world.get_character_transform(physics_character_handle);
            self.transform.position = za.Vec3.fromArray(body_transform.position);
            self.transform.rotation = za.Quat.fromArray(body_transform.rotation);

            {
                const angular_movement = self.angular_input.mul(self.angular_speed).scale(delta_time);
                const up_axis = self.transform.get_up();
                const yaw_rotation = za.Quat.fromAxis(angular_movement.x(), up_axis);
                self.transform.rotation = yaw_rotation.mul(self.transform.rotation).norm();
                const pi_half = std.math.pi / 2.0;
                self.camera_pitch = std.math.clamp(self.camera_pitch + angular_movement.y(), -pi_half, pi_half);
                world.physics_world.set_character_rotation(physics_character_handle, self.transform.rotation.toArray());
            }

            const ground_state = world.physics_world.get_character_ground_state(physics_character_handle);
            if (ground_state == .OnGround) {
                // If player is on ground
                var velocity = za.Vec3.fromArray(world.physics_world.get_character_ground_velocity(physics_character_handle));
                const input_velocity = self.linear_input.norm().mul(self.ground_velocity);
                const input_velocity_ws = self.transform.rotation.rotateVec(za.Vec3.new(input_velocity.x(), 0.0, input_velocity.y()));
                velocity = velocity.add(input_velocity_ws);

                if (self.jump_input) {
                    velocity = velocity.add(self.transform.get_up().scale(self.jump_velocity));
                }

                world.physics_world.set_character_linear_velocity(physics_character_handle, velocity.toArray());
            } else {
                // If player is in the air
                var velocity = za.Vec3.fromArray(world.physics_world.get_character_linear_velocity(physics_character_handle));
                const input_acceleration = self.linear_input.norm().mul(self.air_acceleration).scale(delta_time);
                const input_acceleration_ws = self.transform.rotation.rotateVec(za.Vec3.new(input_acceleration.x(), 0.0, input_acceleration.y()));
                velocity = velocity.add(input_acceleration_ws);
                world.physics_world.set_character_linear_velocity(physics_character_handle, velocity.toArray());
            }
        }

        if (self.render_object) |render_object_handle| {
            world.rendering_world.update_instance(render_object_handle, &self.transform);
        }
        self.jump_input = false;
        self.angular_input = za.Vec2.set(0.0);
    }

    pub fn get_camera_transform(self: Self) Transform {
        const pitch_quat = za.Quat.fromAxis(self.camera_pitch, za.Vec3.X);

        return .{
            .position = self.transform.position,
            .rotation = self.transform.rotation.mul(pitch_quat),
        };
    }
};

pub const Model = struct { mesh: rendering_system.StaticMeshHandle, material: rendering_system.MaterialHandle };

pub const World = struct {
    const Self = @This();

    entities: EntityPool,
    characters: CharacterPool,

    physics_world: physics_system.World,
    rendering_world: rendering_system.Scene,

    pub fn init(
        allocator: std.mem.Allocator,
        backend: *rendering_system.Backend,
    ) Self {
        return .{
            .entities = EntityPool.init(allocator),
            .characters = CharacterPool.init(allocator),
            .physics_world = physics_system.World.init(.{}),
            .rendering_world = backend.create_scene(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit_with_entries();
        self.characters.deinit_with_entries();
        self.physics_world.deinit();
        self.rendering_world.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.physics_world.update(delta_time, 1);
        {
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.body) |body_handle| {
                    const body_transform = self.physics_world.get_body_transform(body_handle);
                    entry.value_ptr.transform.position = za.Vec3.fromArray(body_transform.position);
                    entry.value_ptr.transform.rotation = za.Quat.fromArray(body_transform.rotation);
                }

                if (entry.value_ptr.instance) |instance_handle| {
                    self.rendering_world.update_instance(instance_handle, &entry.value_ptr.transform);
                }
            }
        }

        {
            var iter = self.characters.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.update(self, delta_time);
            }
        }
    }

    pub fn add_entity(
        self: *Self,
        transform: *const Transform,
        body_opt: ?struct {
            shape: physics_system.Shape,
            dynamic: bool,
            sensor: bool = false,
        },
        model_opt: ?Model,
    ) !EntityHandle {
        var body_handle: ?physics_system.BodyHandle = null;
        if (body_opt) |body| {
            body_handle = self.physics_world.add_body(&.{
                .shape = body.shape,
                .position = transform.position.toArray(),
                .rotation = transform.rotation.toArray(),
                .object_layer = if (!body.sensor) 1 else 2,
                .motion_type = if (body.dynamic) .Dynamic else .Static,
                .is_sensor = body.sensor,
                .friction = 0.2,
                .linear_damping = 0.0,
            });
        }

        var instance_handle: ?rendering_system.SceneInstanceHandle = null;
        if (model_opt) |model| {
            instance_handle = try self.rendering_world.add_instace(model.mesh, model.material, transform);
        }

        return try self.entities.insert(.{
            .transform = transform.*,
            .body = body_handle,
            .instance = instance_handle,
        });
    }

    pub fn remove_entity(self: *Self, entity_handle: EntityHandle) !void {
        if (try self.entities.remove(entity_handle)) |entity| {
            if (entity.instance) |instance_handle| {
                try self.rendering_world.remove_instance(instance_handle);
            }
            if (entity.body) |body_handle| {
                self.physics_world.destory_body(body_handle);
            }
        }
    }

    pub fn set_linear_velocity(self: *Self, handle: EntityHandle, linear_velocity: za.Vec3) void {
        if (self.entities.get(handle)) |entity| {
            self.physics_world.set_body_linear_velocity(entity.body.?, linear_velocity.toArray());
        }
    }

    pub fn set_planet_gravity_strength(self: *Self, handle: EntityHandle, gravity_strength: f32) void {
        if (self.entities.get(handle)) |entity| {
            self.physics_world.set_body_volume_gravity_strength(entity.body.?, gravity_strength);
        }
    }

    pub fn add_character(
        self: *Self,
        transform: *const Transform,
        physics_shape: physics_system.Shape,
        model_opt: ?Model,
    ) !CharacterHandle {
        const physics_character =
            self.physics_world.add_character(physics_shape, &.{
            .position = transform.position.toArray(),
            .rotation = transform.rotation.toArray(),
        });

        var render_object: ?rendering_system.SceneInstanceHandle = null;
        if (model_opt) |model| {
            render_object = try self.rendering_world.add_instace(model.mesh, model.material, transform);
        }

        return try self.characters.insert(.{
            .transform = transform.*,
            .render_object = render_object,
            .physics_character = physics_character,
        });
    }

    pub fn remove_character(self: *Self, character_handle: CharacterHandle) !void {
        if (try self.characters.remove(character_handle)) |character| {
            if (character.instance) |instance_handle| {
                try self.rendering_world.remove_instance(instance_handle);
            }
            if (character.physics_character) |physics_character_handle| {
                self.physics_world.destroy_character(physics_character_handle);
            }
        }
    }
};
