const std = @import("std");
const StringHash = @import("string_hash.zig");

pub const Button = enum {
    renderer_reload,

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

pub const InputContext = struct {
    name: StringHash,
    buttons: []const StringHash,
    axes: []const StringHash,
};

pub fn InputContextDevice(comptime DeviceButton: type, comptime DeviceAxis: type, comptime DeviceAxisSettings: type) type {
    const ButtonSettings = struct {
        button1: ?DeviceButton,
        button2: ?DeviceButton,
    };
    _ = ButtonSettings; // autofix

    const AxisSettings = struct {
        axis: ?DeviceAxis,
        settings: DeviceAxisSettings,
        positive_button: ?DeviceButton,
        negitive_button: ?DeviceButton,
    };
    _ = AxisSettings; // autofix

    return struct {
        const Self = @This();
    };
}

const ButtonState2 = struct {
    current: bool = false,
    previous: bool = false,
};

pub const InputContextSystem = struct {
    const Self = @This();

    button_states: std.AutoHashMap(StringHash.HashType, ButtonState2),
    axis_states: std.AutoHashMap(StringHash.HashType, f32),

    pub fn isButtonDown(self: *Self, button: StringHash) bool {
        return self.button_states.get(button.hash).?.current;
    }
    pub fn isButtonPressed(self: *Self, button: StringHash) bool {
        const button_state = self.button_states.get(button.hash).?;
        return button_state.current and !button_state.previous;
    }

    pub fn getAxisValue(self: *Self, axis: StringHash, clamp: bool) f32 {
        var value = self.axis_states.get(axis.hash).?;
        if (clamp) {
            value = std.math.clamp(value, -1.0, 1.0);
        }
        return value;
    }
};

pub const InputSystem = struct {
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        _ = allocator; // autofix
        return .{};
    }

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
    }

    pub fn createContext(self: *Self, context: InputContext) !void {
        _ = self; // autofix
        _ = context; // autofix
    }

    pub fn enableContext(self: *Self, context_name: StringHash) void {
        _ = self; // autofix
        _ = context_name; // autofix
    }

    pub fn getContext(self: *Self, context_name: StringHash) ?*InputContextSystem {
        _ = self; // autofix
        _ = context_name; // autofix
        return null;
    }

    pub fn getTextInput(self: Self) ?[]const u8 {
        _ = self; // autofix
        return null;
    }
};
