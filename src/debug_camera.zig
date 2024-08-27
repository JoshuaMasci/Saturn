const std = @import("std");
const za = @import("zalgebra");

const input = @import("input.zig");

const Transform = @import("transform.zig");
const PerspectiveCamera = @import("camera.zig").PerspectiveCamera;

pub const DebugCamera = struct {
    const Self = @This();

    transform: Transform = Transform.Identity,
    camera: PerspectiveCamera = PerspectiveCamera.Default,

    pitch_yaw: za.Vec2 = za.Vec2.ZERO,

    linear_speed: za.Vec3 = za.Vec3.set(5.0),
    angular_speed: za.Vec3 = za.Vec3.set(std.math.pi),

    linear_speed_fast: za.Vec3 = za.Vec3.set(25.0),
    linear_move_fast: bool = false,

    linear_input: za.Vec3 = za.Vec3.ZERO,
    angular_input: za.Vec3 = za.Vec3.ZERO,

    pub const Default: Self = .{};

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        //std.log.info("Button {} -> {}", .{ event.button, event.state });

        switch (event.button) {
            .debug_camera_fast_move => self.linear_move_fast = event.state == .pressed,
            else => {},
        }
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        //std.log.info("Axis {} -> {:.2}", .{ event.axis, event.get_value(false) });

        switch (event.axis) {
            .debug_camera_left_right => self.linear_input.data[0] = event.get_value(true),
            .debug_camera_up_down => self.linear_input.data[1] = event.get_value(true),
            .debug_camera_forward_backward => self.linear_input.data[2] = event.get_value(true),

            .debug_camera_pitch => self.angular_input.data[0] = event.get_value(false),
            .debug_camera_yaw => self.angular_input.data[1] = event.get_value(false),
            else => {},
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        const linear_speed = if (self.linear_move_fast) self.linear_speed_fast else self.linear_speed;
        const linear_movement = self.transform.rotation.rotateVec(self.linear_input.mul(linear_speed).scale(delta_time));
        self.transform.position = self.transform.position.add(linear_movement);

        const angular_rotation = self.angular_input.mul(self.angular_speed).scale(delta_time);

        self.pitch_yaw = self.pitch_yaw.add(angular_rotation.toVec2());

        // Clamp pitch and keep roation between 0->360 degrees
        const pi_half = std.math.pi / 2.0;
        const pi_2 = std.math.pi * 2.0;
        self.pitch_yaw = za.Vec2.new(std.math.clamp(self.pitch_yaw.x(), -pi_half, pi_half), @mod(self.pitch_yaw.y(), pi_2));

        const pitch_quat = za.Quat.fromAxis(self.pitch_yaw.x(), za.Vec3.X);
        const yaw_quat = za.Quat.fromAxis(self.pitch_yaw.y(), za.Vec3.Y);
        self.transform.rotation = yaw_quat.mul(pitch_quat).norm();

        // Axis events should fire each frame they are active, so the input is reset each update
        self.angular_input = za.Vec3.set(0.0);
    }
};
