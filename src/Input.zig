const std = @import("std");

id: ?u32 = null,
left_stick: [2]f32 = @splat(0),
right_stick: [2]f32 = @splat(0),
shoulder: [2]bool = @splat(false),

pub fn getInput(gamepad: *const @This()) struct { linear: [3]f32, angular: [3]f32 } {
    return .{ .linear = .{
        axisDeadzone(-gamepad.left_stick[0]),
        buttonAxis(gamepad.shoulder),
        axisDeadzone(-gamepad.left_stick[1]),
    }, .angular = .{
        axisDeadzone(gamepad.right_stick[1]),
        axisDeadzone(-gamepad.right_stick[0]),
        0,
    } };
}

pub fn axisDeadzone(value: f32) f32 {
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
pub fn buttonAxis(values: [2]bool) f32 {
    //Yes im being overly clever here
    return @floatFromInt(@as(i8, @intFromBool(values[1])) - @as(i8, @intFromBool(values[0])));
}
