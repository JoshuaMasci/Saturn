const std = @import("std");

const zm = @import("zmath");

const Camera = @import("rendering/camera.zig").Camera;
const Transform = @import("transform.zig");

const Self = @This();

camera: Camera = .Default,
transform: Transform = .{},

linear_speed: zm.Vec = @splat(5),
angular_speed: zm.Vec = @splat(std.math.pi),

linear_input: zm.Vec = @splat(0),
angular_input: zm.Vec = @splat(0),

//Gamepad
gamepad: struct {
    id: ?u32 = null,
    left_stick: [2]f32 = @splat(0),
    right_stick: [2]f32 = @splat(0),
    shoulder: [2]bool = @splat(false),
} = .{},

pub fn update(self: *Self, delta_time: f32) void {
    const linear_input: zm.Vec = .{
        axisDeadzone(-self.gamepad.left_stick[0]),
        buttonAxis(self.gamepad.shoulder),
        axisDeadzone(-self.gamepad.left_stick[1]),
        0,
    };

    const angular_input: zm.Vec = .{
        axisDeadzone(self.gamepad.right_stick[1]),
        axisDeadzone(-self.gamepad.right_stick[0]),
        0,
        0,
    };

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

    const pitch_quat = zm.quatFromAxisAngle(.{ 1, 0, 0, 0 }, pitch_yaw[0]);
    const yaw_quat = zm.quatFromAxisAngle(.{ 0, 1, 0, 0 }, pitch_yaw[1]);
    self.transform.rotation = zm.normalize4(zm.qmul(pitch_quat, yaw_quat));
}

fn axisDeadzone(value: f32) f32 {
    if (@abs(value) > 0.1) {
        return value;
    }
    return 0.0;
}

// Truth Table
// | B0 | B1 |  V |
// | F  | F  |  0 |
// | T  | F  | -1 |
// | F  | T  |  1 |
// | T  | T  |  0 |
/// Turns 2 button into an -1 to 1 axis
fn buttonAxis(values: [2]bool) f32 {
    //Yes im being overly clever here
    return @floatFromInt(@as(i8, @intFromBool(values[1])) - @as(i8, @intFromBool(values[0])));
}
