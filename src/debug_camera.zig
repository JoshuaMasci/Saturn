const std = @import("std");

const zm = @import("zmath");

const Camera = @import("rendering/camera.zig").Camera;
const Transform = @import("transform.zig");

const Self = @This();

camera: Camera = .Default,
transform: Transform = .{},

linear_speed: zm.Vec = zm.splat(zm.Vec, 5.0),
angular_speed: zm.Vec = zm.splat(zm.Vec, std.math.pi),

const sdl3 = @import("platform/sdl3.zig");
pub fn update(self: *Self, input: *sdl3.Input, delta_time: f32) void {
    const x_axis_input = getControllerAxis(input, .left_x);
    const y_axis_input = getControllerButtonAxis(input, .right_shoulder, .left_shoulder);
    const z_axis_input = getControllerAxis(input, .left_y);
    var linear_input: zm.Vec = .{ -x_axis_input, y_axis_input, -z_axis_input, 0 };
    const linear_input_len = zm.length3(linear_input);
    if (linear_input_len[0] < 0.25) {
        linear_input = @splat(0.0);
    }

    const pitch_input = getControllerAxis(input, .right_y);
    const yaw_input = getControllerAxis(input, .right_x);
    var angular_input: zm.Vec = .{ pitch_input, -yaw_input, 0, 0 };
    const angular_input_len = zm.length3(angular_input);
    if (angular_input_len[0] < 0.25) {
        angular_input = @splat(0.0);
    }

    self.transform.position += zm.rotate(self.transform.rotation, linear_input * self.linear_speed * zm.f32x4s(delta_time));

    const angular_rotation = angular_input * self.angular_speed * zm.f32x4s(delta_time);

    const forward = self.transform.getForward();
    const x = forward[0];
    const y = forward[1];
    const z = forward[2];
    const xz = zm.loadArr2(.{ x, z });

    const pitch = -std.math.atan2(y, zm.length2(xz)[0]);
    const yaw = std.math.atan2(x, z);
    var pitch_yaw = zm.loadArr2(.{ pitch, yaw }) + angular_rotation;

    // Clamp pitch and keep roation between 0->360 degrees
    const pi_2 = std.math.pi * 2.0;
    const max_angle: f32 = std.math.degreesToRadians(89.9);
    pitch_yaw = zm.loadArr2(.{ std.math.clamp(pitch_yaw[0], -max_angle, max_angle), @mod(pitch_yaw[1], pi_2) });

    const pitch_quat = zm.quatFromAxisAngle(zm.f32x4(1, 0, 0, 0), pitch_yaw[0]);
    const yaw_quat = zm.quatFromAxisAngle(zm.f32x4(0, 1, 0, 0), pitch_yaw[1]);
    self.transform.rotation = zm.normalize4(zm.qmul(pitch_quat, yaw_quat));
}

pub fn getControllerAxis(input: *sdl3.Input, axis: sdl3.Controller.Axis) f32 {
    const controllers = input.controllers.values();
    if (controllers.len > 0) {
        const controller = controllers[0];
        const value = controller.axis_state[@intFromEnum(axis)].value;
        if (@abs(value) > 0.1) {
            return value;
        }
    }

    return 0.0;
}

pub fn getControllerButtonAxis(input: *sdl3.Input, pos: sdl3.Controller.Button, neg: sdl3.Controller.Button) f32 {
    const controllers = input.controllers.values();
    if (controllers.len > 0) {
        const controller = controllers[0];
        const pos_state = controller.button_state[@intFromEnum(pos)].is_pressed;
        const neg_state = controller.button_state[@intFromEnum(neg)].is_pressed;

        if (pos_state and !neg_state) {
            return 1.0;
        } else if (!pos_state and neg_state) {
            return -1.0;
        }
    }

    return 0.0;
}
