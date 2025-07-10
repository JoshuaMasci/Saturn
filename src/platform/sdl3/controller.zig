const std = @import("std");

const sdl3 = @import("../sdl3.zig");
const c = sdl3.c;
const ButtonState = sdl3.ButtonState;
const AxisState = sdl3.AxisState;

pub const Button = enum(usize) {
    south = 0,
    east = 1,
    west = 2,
    north = 3,
    back = 4,
    guide = 5,
    start = 6,
    left_stick = 7,
    right_stick = 8,
    left_shoulder = 9,
    right_shoulder = 10,
    d_pad_up = 11,
    d_pad_down = 12,
    d_pad_left = 13,
    d_pad_right = 14,
    misc1 = 15,
    right_paddle1 = 16,
    left_paddle1 = 17,
    right_paddle2 = 18,
    left_paddle2 = 19,
    touchpad = 20,
    misc2 = 21,
    misc3 = 22,
    misc4 = 23,
    misc5 = 24,
    misc6 = 25,
};

pub const Axis = enum(usize) {
    left_x = 0,
    left_y = 1,
    right_x = 2,
    right_y = 3,
    left_trigger = 4,
    right_trigger = 5,
};

pub const AxisButtonSettings = struct {
    axis: Axis,
    threshold: f32 = 0.9,
    positive: bool = true,
};

pub const AxisSettings = struct {
    axis: Axis,
    sensitivity: f32 = 1.0,
    deadzone: f32 = 0.1,
    invert: bool = false,
};

pub const ButtonAxis = struct {
    pos: ?Button = null,
    neg: ?Button = null,
};

pub const ButtonBinding = union(enum) {
    button: Button,
    axis: AxisButtonSettings,
};

pub const AxisBinding = union(enum) {
    axis: AxisSettings,
    buttons: ButtonAxis,
};

const Self = @This();

allocator: std.mem.Allocator,

name: []u8,
joystick: c.SDL_JoystickID,
gamepad: *c.SDL_Gamepad,

button_state: [c.SDL_GAMEPAD_BUTTON_COUNT]ButtonState = @splat(.{}),
axis_state: [c.SDL_GAMEPAD_AXIS_COUNT]AxisState = @splat(.{}),

pub fn init(allocator: std.mem.Allocator, gamepad: *c.SDL_Gamepad) !Self {
    const name_ref = c.SDL_GetGamepadName(gamepad);
    const name = try allocator.dupe(u8, std.mem.span(name_ref));
    const joystick = c.SDL_GetGamepadID(gamepad);

    return .{
        .allocator = allocator,
        .name = name,
        .joystick = joystick,
        .gamepad = gamepad,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.name);
    c.SDL_CloseGamepad(self.gamepad);
}

pub fn beginFrame(self: *Self) void {
    for (&self.button_state) |*button_state| {
        button_state.was_pressed_last_frame = button_state.is_pressed;
    }
}

pub fn proccessEvent(self: *Self, event: *c.SDL_Event) void {
    switch (event.type) {
        c.SDL_EVENT_GAMEPAD_BUTTON_UP, c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
            self.button_state[event.gbutton.button].timestamp = event.gbutton.timestamp;
            self.button_state[event.gbutton.button].is_pressed = event.gbutton.down;
        },
        c.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
            const i_value: f32 = @floatFromInt(event.gaxis.value);
            const f_value: f32 = i_value / std.math.maxInt(i16);
            self.axis_state[event.gaxis.axis].timestamp = event.gaxis.timestamp;
            self.axis_state[event.gaxis.axis].value = f_value;
        },
        else => {},
    }
}
