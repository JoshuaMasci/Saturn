const std = @import("std");
const za = @import("zalgebra");

const ObjectPool = @import("object_pool.zig").ObjectPool;
const Transform = @import("transform.zig");

const physics_system = @import("physics.zig");
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

    //Ground Movement State
    linear_speed: za.Vec2 = za.Vec2.set(5.0),
    jump_velocity: f32 = 10.0,
    max_jumps: u32 = 1,

    linear_input: za.Vec2 = za.Vec2.ZERO,
    jump_input: bool = false,
    jump_count: u32 = 0,

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
            else => {},
        }
    }

    pub fn update(self: *Self, world: *World, delta_time: f32) void {
        if (self.physics_character) |character_handle| {
            var character = world.physics_world.get_character(character_handle).?;

            var gravity_vector = self.transform.rotation.rotateVec(za.Vec3.NEG_Y).scale(9.8);

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

            character.set_gravity(gravity_vector);
        }

        self.jump_input = false;
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
            .physics_world = physics_system.World.init(allocator, .{
                .max_bodies = 1024 * 4,
                .num_body_mutexes = 0,
                .max_body_pairs = 1024 * 4,
                .max_contact_constraints = 1024 * 2,
            }) catch |err| {
                std.debug.panic("Failed to create physics world: {}", .{err});
            },
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
        {
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.body) |body_handle| {
                    const body = self.physics_world.get_body(body_handle);
                    body.set_transform_if_changed(entry.value_ptr.transform.get_unscaled());
                }
            }
        }

        {
            var iter = self.characters.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.physics_character) |character_handle| {
                    var character = self.physics_world.get_character(character_handle).?;
                    character.set_transform(entry.value_ptr.transform.get_unscaled());
                }
                entry.value_ptr.update(self, delta_time);
            }
        }

        self.physics_world.update(delta_time) catch |err| {
            std.log.err("Failed to update physics world: {}", .{err});
        };

        {
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.body) |body_handle| {
                    entry.value_ptr.transform.apply_unscaled(&self.physics_world.get_body(body_handle).get_transform());
                }
            }
        }

        {
            var iter = self.characters.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.physics_character) |character_handle| {
                    var character = self.physics_world.get_character(character_handle).?;
                    entry.value_ptr.transform.apply_unscaled(&character.get_transform());
                }
            }
        }

        {
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.instance) |instance_handle| {
                    self.rendering_world.update_instance(instance_handle, &entry.value_ptr.transform);
                }
            }
        }

        {
            var iter = self.characters.iterator();
            while (iter.next()) |entry| {
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
        },
        model_opt: ?Model,
    ) !EntityHandle {
        var body_handle: ?physics_system.BodyHandle = null;
        if (body_opt) |body| {
            const motion_type: physics_system.BodyMotionType = switch (body.dynamic) {
                true => .dynamic,
                false => .static,
            };

            body_handle = try self.physics_world.create_body(transform.get_unscaled(), body.shape, .{
                .motion_type = motion_type,
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

    pub fn add_character(
        self: *Self,
        transform: *const Transform,
        physics_shape: physics_system.Shape,
        model_opt: ?Model,
    ) !CharacterHandle {
        const physics_character = try self.physics_world.create_character(transform.get_unscaled(), physics_shape);

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

//TODO: use this later?
// pub const NodePool = object_pool.ObjectPool(u16, Node);
// pub const NodeHandle = NodePool.Handle;

// pub const NodeComponents = struct {
//     model: ?void,
//     collider: ?void,
// };

// pub const Node = struct {
//     name: ?[]const u8,
//     local_transform: Transform,
//     components: NodeComponents,

//     parent: ?NodeHandle,
//     childen: std.ArrayList(NodeHandle),
// };

// pub const EntityComponents = struct {
//     character: ?void,
//     body: ?void,
// };

// pub const EntityData = struct {
//     name: ?[]const u8,
//     transform: Transform,
//     components: EntityComponents,

//     root_nodes: std.ArrayList(NodeHandle),
//     node_pool: NodePool,
// };

// pub const EntitySystems = struct {};
// pub const Entity = struct {
//     data: EntityData,
//     systems: EntitySystems,
// };

// pub const WorldData = struct {};

// pub const World = struct {
//     data: WorldData,
//     entity_pool: std.ArrayList(?Entity),
// };
