const std = @import("std");
const zm = @import("zmath");

const input = @import("input.zig");

const Transform = @import("transform.zig");
const PerspectiveCamera = @import("camera.zig").PerspectiveCamera;

pub const DebugCamera = struct {
    const Self = @This();

    transform: Transform = Transform.Identity,
    camera: PerspectiveCamera = PerspectiveCamera.Default,

    pitch_yaw: zm.Vec = zm.splat(zm.Vec, 0.0),

    linear_speed: zm.Vec,
    angular_speed: zm.Vec,

    linear_input: zm.Vec,
    angular_input: zm.Vec,

    pub const Default: Self = .{
        .linear_speed = zm.splat(zm.Vec, 5.0),
        .angular_speed = zm.splat(zm.Vec, std.math.pi),
        .linear_input = zm.splat(zm.Vec, 0.0),
        .angular_input = zm.splat(zm.Vec, 0.0),
    };

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        _ = self;
        std.log.info("Button {} -> {}", .{ event.button, event.state });
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        //std.log.info("Axis {} -> {:.2}", .{ event.axis, event.get_value(false) });

        switch (event.axis) {
            .debug_camera_left_right => self.linear_input[0] = event.get_value(true),
            .debug_camera_up_down => self.linear_input[1] = event.get_value(true),
            .debug_camera_forward_backward => self.linear_input[2] = event.get_value(true),

            .debug_camera_pitch => self.angular_input[0] = event.get_value(false),
            .debug_camera_yaw => self.angular_input[1] = event.get_value(false),
            else => {},
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        const delta_time_vec = zm.splat(zm.Vec, delta_time);

        const linear_movement = zm.rotate(self.transform.rotation, (self.linear_input * self.linear_speed) * delta_time_vec);
        self.transform.position += linear_movement;

        const angular_rotation = (self.angular_input * self.angular_speed) * delta_time_vec;

        self.pitch_yaw += angular_rotation;

        const pi_half = std.math.pi / 2.0;
        // Clamp pitch
        self.pitch_yaw[0] = std.math.clamp(self.pitch_yaw[0], -pi_half, pi_half);

        // Return rotation to
        self.pitch_yaw[1] = zm.modAngle(self.pitch_yaw[1]);

        const pitch_quat = zm.quatFromAxisAngle(zm.loadArr3(.{ 1.0, 0.0, 0.0 }), self.pitch_yaw[0]);
        const yaw_quat = zm.quatFromAxisAngle(zm.loadArr3(.{ 0.0, 1.0, 0.0 }), self.pitch_yaw[1]);
        self.transform.rotation = zm.normalize4(zm.qmul(pitch_quat, yaw_quat));

        // Axis events should fire each frame they are active, so the input is reset each update
        self.angular_input = zm.splat(zm.Vec, 0.0);
    }
};
