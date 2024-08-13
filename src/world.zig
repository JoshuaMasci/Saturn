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

    planet_handle: ?EntityHandle = null,

    //TODO: 3D movement state

    //Ground Movement State
    linear_speed: za.Vec2 = za.Vec2.set(5.0),
    angular_speed: za.Vec2 = za.Vec2.set(std.math.pi),

    jump_velocity: f32 = 15.0,
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
                self.jump_input = event.state.is_down();
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
        const gravity_strength = 9.8;

        if (self.planet_handle) |planet_handle| {
            if (world.entities.getPtr(planet_handle)) |planet| {
                const current_up = self.transform.get_up();
                const new_up = self.transform.position.sub(planet.transform.position).norm();

                const cross_vector = current_up.cross(new_up);
                const angle = new_up.getAngle(current_up);
                if (!std.math.isNan(angle) and angle != 0.0) {
                    //std.log.info("cross: {d:.3} -> angle: {d:.3}", .{ cross_vector.toArray(), angle });
                    const rotation_amount = za.Quat.fromAxis(angle, cross_vector);
                    //std.log.info("Pre: {d:.3} -> Amount: {d:.3}", .{ self.transform.rotation.toArray(), rotation_amount.toArray() });
                    self.transform.rotation = rotation_amount.mul(self.transform.rotation);
                    //std.log.info("After: {d:.3}", .{self.transform.rotation.toArray()});
                }
            }
        }

        if (self.physics_character) |character_handle| {
            var character = world.physics_world.get_character(character_handle).?;

            const angular_movement = self.angular_input.mul(self.angular_speed).scale(delta_time);

            const up_axis = self.transform.get_up();
            const yaw_rotation = za.Quat.fromAxis(angular_movement.x(), up_axis);
            self.transform.rotation = yaw_rotation.mul(self.transform.rotation).norm();

            const pi_half = std.math.pi / 2.0;
            self.camera_pitch = std.math.clamp(self.camera_pitch + angular_movement.y(), -pi_half, pi_half);

            var gravity_vector = up_axis.scale(-1.0 * gravity_strength);

            //std.log.info("Character Ground State: {}", .{character.get_ground_state()});

            if (character.get_ground_state() == .on_ground) {
                var input_velocity = self.linear_input.norm().mul(self.linear_speed);

                var new_velocity = za.Vec3.new(input_velocity.x(), 0.0, input_velocity.y());

                if (self.jump_input) {
                    new_velocity = new_velocity.add(za.Vec3.Y.scale(self.jump_velocity));
                }

                character.set_linear_velocity(self.transform.rotation.rotateVec(new_velocity));
            } else {
                character.add_linear_velocity(gravity_vector.scale(delta_time));
            }

            character.set_rotation(self.transform.rotation);
            character.set_gravity(gravity_vector);
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
                if (entry.value_ptr.physics_character) |physics_character_handle| {
                    const body_transform = self.physics_world.get_character_transform(physics_character_handle);
                    entry.value_ptr.transform.position = za.Vec3.fromArray(body_transform.position);
                    entry.value_ptr.transform.rotation = za.Quat.fromArray(body_transform.rotation);

                    const ground_state = self.physics_world.get_character_ground_state(physics_character_handle);
                    if (ground_state == .OnGround) {
                        // If player is on ground
                        //std.log.info("Player On Ground", .{});

                        //TODO: player move logic
                        var velocity = za.Vec3.fromArray(self.physics_world.get_character_ground_velocity(physics_character_handle));
                        velocity = velocity.add(entry.value_ptr.transform.rotation.rotateVec(za.Vec3.Z.scale(5.0)));
                        self.physics_world.set_character_linear_velocity(physics_character_handle, velocity.toArray());
                    } else {
                        // If player is in the air
                        //std.log.info("Player In Air", .{});

                        //TODO: player air move logic
                        var velocity = za.Vec3.fromArray(self.physics_world.get_character_linear_velocity(physics_character_handle));
                        velocity = velocity.add(entry.value_ptr.transform.rotation.rotateVec(za.Vec3.Z.scale(10.0 * delta_time)));
                        self.physics_world.set_character_linear_velocity(physics_character_handle, velocity.toArray());
                    }
                }

                if (entry.value_ptr.render_object) |render_object_handle| {
                    self.rendering_world.update_instance(render_object_handle, &entry.value_ptr.transform);
                }
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
