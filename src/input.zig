const std = @import("std");
const StringHash = @import("string_hash.zig");

pub const Button = enum {
    debug_camera_interact,
    debug_camera_fast_move,
    player_move_jump,
};

pub const Axis = enum {
    debug_camera_forward_backward,
    debug_camera_left_right,
    debug_camera_up_down,

    debug_camera_pitch,
    debug_camera_yaw,
    debug_camera_roll,

    player_move_forward_backward,
    player_move_left_right,

    player_rotate_yaw,
    player_rotate_pitch,
};

pub const ButtonState = enum {
    pressed,
    released,

    pub fn is_down(self: @This()) bool {
        return self == .pressed;
    }
};

pub const AxisDirection = enum {
    positve,
    negitive,
};

pub const ButtonAxisState = struct {
    positve: ButtonState,
    negitive: ButtonState,

    pub const Default: @This() = .{ .positve = .released, .negitive = .released };

    pub fn update(self: *@This(), dir: AxisDirection, state: ButtonState) void {
        switch (dir) {
            .positve => self.positve = state,
            .negitive => self.negitive = state,
        }
    }

    pub fn get_value(self: @This()) f32 {
        var value: f32 = 0.0;
        if (self.positve == .pressed) {
            value += 1.0;
        }
        if (self.negitive == .pressed) {
            value -= 1.0;
        }
        return value;
    }
};

pub const ButtonEvent = struct {
    button: Button,
    state: ButtonState,
};

pub const AxisEvent = struct {
    axis: Axis,
    value: f32,

    pub fn get_value(self: @This(), clamp: bool) f32 {
        if (clamp) {
            return std.math.clamp(self.value, -1.0, 1.0);
        } else {
            return self.value;
        }
    }
};

pub const ButtonBinding = union(enum) {
    button: Button,
    axis: struct {
        axis: Axis,
        dir: AxisDirection,
    },
};
