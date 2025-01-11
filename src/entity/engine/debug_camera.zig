const std = @import("std");
const za = @import("zalgebra");

const Node = @import("../node.zig");
const Entity = @import("../entity.zig");

const input = @import("../../input.zig");

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

    pub fn update(self: *Self, data: Entity.UpdateData) void {
        if (data.stage == .post_physics) {
            if (self.cast_ray) {
                if (data.world.systems.physics) |physics_world| {
                    if (physics_world.castRayIgnoreEntity(
                        1,
                        data.entity,
                        data.entity.transform.position,
                        data.entity.transform.get_forward().scale(10.0),
                    )) |hit| {
                        std.log.info("Hit Entity: {}", .{hit});
                    }
                }
                self.cast_ray = false;
            }
        }

        if (data.stage != .pre_physics)
            return;

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
