const std = @import("std");
const StringHash = @import("string_hash.zig");

pub const Button = enum {
    player_interact,
    player_move_jump,
};

pub const Axis = enum {
    player_move_left_right,
    player_move_up_down,
    player_move_forward_backward,

    player_rotate_yaw,
    player_rotate_pitch,
};

pub const ButtonState = enum {
    pressed,
    released,
};

pub const AxisDirection = enum {
    positve,
    negitive,

    pub fn get_value(self: @This()) f32 {
        return if (self == .positve) 1.0 else -1.0;
    }
};

pub const ButtonAxisState = struct {
    const Self = @This();

    const InputType = enum(u1) {
        button,
        axis,
    };
    last_input: ?InputType = null,
    positve_button: ButtonState = .released,
    negitive_button: ButtonState = .released,
    axis_value: f32 = 0.0,

    pub fn update_button(self: *Self, dir: AxisDirection, state: ButtonState) void {
        self.last_input = .button;
        switch (dir) {
            .positve => self.positve = state,
            .negitive => self.negitive = state,
        }
    }

    pub fn update_axis(self: *Self, value: f32) void {
        self.last_input = .axis;
        self.axis_value = value;
    }

    pub fn get_value(self: Self) f32 {
        if (self.last_input) |last_input| {
            switch (last_input) {
                .button => {
                    var value: f32 = 0.0;
                    if (self.positve == .pressed) {
                        value += 1.0;
                    }
                    if (self.negitive == .pressed) {
                        value -= 1.0;
                    }
                    return value;
                },
                .axis => {
                    return self.axis_value;
                },
            }
        } else {
            return 0.0;
        }
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

pub const AxisBinding = struct {
    axis: Axis,
    sensitivity: f32 = 1.0,
    invert: bool = false,

    pub fn calc_value(self: @This(), raw_input: f32) f32 {
        const sign: f32 = if (self.invert) -1.0 else 1.0;
        return raw_input * self.sensitivity * sign;
    }
};
