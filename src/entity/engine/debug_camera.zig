const std = @import("std");
const za = @import("zalgebra");

const input = @import("../../input.zig");

const Node = @import("../node.zig");
const Entity = @import("../entity.zig");
const World = @import("../world.zig");
const physics = @import("physics.zig");
const UpdateStage = @import("../universe.zig").UpdateStage;

pub const DebugCameraEntitySystem = struct {
    const Self = @This();

    linear_speed: za.Vec3 = za.Vec3.set(5.0),
    angular_speed: za.Vec3 = za.Vec3.set(std.math.pi),

    pitch_yaw: za.Vec2 = za.Vec2.ZERO,
    linear_input: za.Vec3 = za.Vec3.ZERO,
    angular_input: za.Vec3 = za.Vec3.ZERO,

    camera_node: ?Node.Handle = null,

    cast_ray: bool = false,

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
    }

    pub fn updateParallel(self: *Self, stage: UpdateStage, entity: *Entity, world: *const World, delta_time: f32) void {
        _ = world; // autofix

        if (stage != .pre_physics)
            return;

        const linear_speed = entity.transform.rotation.rotateVec(self.linear_input.mul(self.linear_speed));
        if (entity.systems.get(physics.PhysicsEntitySystem)) |entity_physics| {
            entity_physics.linear_velocity = linear_speed;
            entity_physics.angular_velocity = za.Vec3.ZERO;
        } else {
            entity.transform.position = entity.transform.position.add(linear_speed.scale(delta_time));
        }

        const angular_rotation = self.angular_input.mul(self.angular_speed).scale(delta_time);

        self.pitch_yaw = self.pitch_yaw.add(angular_rotation.toVec2());

        // Clamp pitch and keep roation between 0->360 degrees
        const pi_half = std.math.pi / 2.0;
        const pi_2 = std.math.pi * 2.0;
        self.pitch_yaw = za.Vec2.new(std.math.clamp(self.pitch_yaw.x(), -pi_half, pi_half), @mod(self.pitch_yaw.y(), pi_2));

        const pitch_quat = za.Quat.fromAxis(self.pitch_yaw.x(), za.Vec3.X);
        const yaw_quat = za.Quat.fromAxis(self.pitch_yaw.y(), za.Vec3.Y);
        entity.transform.rotation = yaw_quat.mul(pitch_quat).norm();

        // Axis events should fire each frame they are active, so the input is reset each update
        self.angular_input = za.Vec3.set(0.0);
    }

    pub fn updateExclusive(self: *Self, stage: UpdateStage, entity: *Entity, world: *World, delta_time: f32) void {
        _ = delta_time; // autofix

        if (stage == .post_physics) {
            if (self.cast_ray) {
                if (world.systems.get(physics.PhysicsWorldSystem)) |physics_world| {
                    if (physics_world.castRayIgnoreEntity(
                        1,
                        entity,
                        entity.transform.position,
                        entity.transform.get_forward().scale(10.0),
                    )) |hit| {
                        const hit_entity = world.entities.get(hit.entity_handle).?;
                        const node = hit_entity.nodes.pool.getPtr(hit.node_handle).?;
                        if (node.components.airlock != null) {
                            std.log.info("Hit Airlock!!!: {}", .{hit});
                        }
                    }
                }
                self.cast_ray = false;
            }
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
