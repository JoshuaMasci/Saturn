const std = @import("std");

const input = @import("../input3.zig");
const App = @import("../app.zig").App;

pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");

    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

pub const Platform = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    should_quit: bool,
    keyboard_mouse_device: *KeyboardMouse,
    input_devices: std.ArrayList(input.InputDevice),

    pub fn init(allocator: std.mem.Allocator) !Self {
        const version = c.SDL_GetVersion();
        std.log.info("Starting sdl {}.{}.{}", .{ c.SDL_VERSIONNUM_MAJOR(version), c.SDL_VERSIONNUM_MINOR(version), c.SDL_VERSIONNUM_MICRO(version) });

        if (!c.SDL_Init(c.SDL_INIT_EVENTS | c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD | c.SDL_INIT_HAPTIC)) {
            return error.sdlInitFailed;
        }

        const keyboard_mouse_device = try allocator.create(KeyboardMouse);
        keyboard_mouse_device.* = try KeyboardMouse.init(allocator);

        var input_devices = try std.ArrayList(input.InputDevice).initCapacity(allocator, 1);
        input_devices.appendAssumeCapacity(keyboard_mouse_device.getInputDevices());

        return .{
            .allocator = allocator,
            .should_quit = false,
            .keyboard_mouse_device = keyboard_mouse_device,
            .input_devices = input_devices,
        };
    }

    pub fn deinit(self: *Self) void {
        self.input_devices.deinit();
        self.keyboard_mouse_device.deinit();
        self.allocator.destroy(self.keyboard_mouse_device);

        std.log.info("Quiting sdl", .{});
        c.SDL_Quit();
    }

    pub fn proccessEvents(self: *Self, app: *App) !void {
        _ = app; // autofix

        self.keyboard_mouse_device.beginFrame();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    self.should_quit = true;
                },
                c.SDL_EVENT_KEY_UP, c.SDL_EVENT_KEY_DOWN => {
                    if (self.keyboard_mouse_device.keyboard) |keyboard| {
                        keyboard.proccessEvent(&event);
                    }
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_WHEEL, c.SDL_EVENT_MOUSE_MOTION => {
                    if (self.keyboard_mouse_device.mouse) |mouse| {
                        mouse.proccessEvent(&event);
                    }
                },
                else => {},
            }
        }
    }

    pub fn getInputDevices(self: Self) []const input.InputDevice {
        return self.input_devices.items;
    }
};

const KeyboardMouse = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    keyboard: ?*Keyboard = null,
    mouse: ?*Mouse = null,

    fn init(allocator: std.mem.Allocator) !Self {
        var keyboard: ?*Keyboard = null;
        if (c.SDL_HasKeyboard()) {
            keyboard = try allocator.create(Keyboard);
            keyboard.?.* = Keyboard{};
        }

        var mouse: ?*Mouse = null;
        if (c.SDL_HasMouse()) {
            mouse = try allocator.create(Mouse);
            mouse.?.* = Mouse{};
        }

        return .{
            .allocator = allocator,
            .keyboard = keyboard,
            .mouse = mouse,
        };
    }

    fn deinit(self: *Self) void {
        if (self.keyboard) |keyboard| {
            self.allocator.destroy(keyboard);
        }
        if (self.mouse) |mouse| {
            self.allocator.destroy(mouse);
        }
    }

    fn beginFrame(self: *Self) void {
        if (self.keyboard) |keyboard| {
            keyboard.beginFrame();
        }

        if (self.mouse) |mouse| {
            mouse.beginFrame();
        }
    }

    fn getButton(ptr: *anyopaque, context_hash: u32, button: u32) ?input.DeviceButtonState {
        _ = context_hash; // autofix

        const self: *Self = @alignCast(@ptrCast(ptr));
        if (self.keyboard) |keyboard| {
            if (button == 0) {
                return keyboard.button_state[c.SDL_SCANCODE_E].toDeviceState();
            }
        }

        return null;
    }

    fn getAxis(ptr: *anyopaque, context_hash: u32, axis: u32) ?input.DeviceAxisState {
        _ = context_hash; // autofix

        const self: *Self = @alignCast(@ptrCast(ptr));

        if (self.keyboard) |keyboard| {
            switch (axis) {
                0 => return keyboard.tempKeyAxis(c.SDL_SCANCODE_A, c.SDL_SCANCODE_D),
                1 => return keyboard.tempKeyAxis(c.SDL_SCANCODE_LSHIFT, c.SDL_SCANCODE_SPACE),
                2 => return keyboard.tempKeyAxis(c.SDL_SCANCODE_W, c.SDL_SCANCODE_S),
                else => {},
            }
        }

        if (self.mouse) |mouse| {
            if (axis == 3 or axis == 4) {
                switch (mouse.axis_state) {
                    .active => |axes| {
                        if (axis == 3) {
                            var state = axes[0];
                            state.value *= -1.0;
                            return state;
                        } else {
                            return axes[1];
                        }
                    },
                    .previous => return .{},
                    .idle => {},
                }
            }
        }

        return null;
    }

    pub fn getInputDevices(self: *Self) input.InputDevice {
        return .{
            .ptr = @ptrCast(self),
            .get_button_state = &Self.getButton,
            .get_axis_state = &Self.getAxis,
        };
    }
};

const ButtonState = struct {
    timestamp: u64 = 0,
    is_pressed: bool = false,
    was_pressed_last_frame: bool = false,

    pub fn toDeviceState(self: @This()) input.DeviceButtonState {
        return .{
            .timestamp = self.timestamp,
            .state = if (self.is_pressed and !self.was_pressed_last_frame) .pressed else if (self.is_pressed) .held else .released,
        };
    }
};

const Keyboard = struct {
    const Self = @This();

    button_state: [c.SDL_SCANCODE_COUNT]ButtonState = .{.{}} ** c.SDL_SCANCODE_COUNT,

    fn beginFrame(self: *Self) void {
        for (&self.button_state) |*button_state| {
            button_state.was_pressed_last_frame = button_state.is_pressed;
        }
    }

    fn proccessEvent(self: *Self, event: *c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_KEY_UP, c.SDL_EVENT_KEY_DOWN => {
                self.button_state[event.key.scancode].timestamp = event.key.timestamp;
                self.button_state[event.key.scancode].is_pressed = event.key.down;
            },
            else => {},
        }
    }

    //TODO: remove this once an actual input config is working
    fn tempKeyAxis(self: Self, pos_key: usize, neg_key: usize) input.DeviceAxisState {
        var state: input.DeviceAxisState = .{};

        if (self.button_state[pos_key].is_pressed) {
            state.value += 1.0;
            state.timestamp = @max(state.timestamp, self.button_state[pos_key].timestamp);
        }

        if (self.button_state[neg_key].is_pressed) {
            state.value -= 1.0;
            state.timestamp = @max(state.timestamp, self.button_state[neg_key].timestamp);
        }

        return state;
    }
};

const MouseMovementState = union(enum) {
    active: [2]input.DeviceAxisState, // Currently moving this frame
    previous: void, // Moved in the last frame, not this one
    idle: void, // No recent movement
};

const Mouse = struct {
    const Self = @This();

    button_state: [5]ButtonState = .{.{}} ** 5,
    axis_state: MouseMovementState = .idle,

    fn beginFrame(self: *Self) void {
        for (&self.button_state) |*button_state| {
            button_state.was_pressed_last_frame = button_state.is_pressed;
        }

        // Clears mouse movement for this new frame
        // .last is used if the mouse moved last frame, so this frame the mouse axis is reset to 0,0 this frame
        self.axis_state = switch (self.axis_state) {
            .active => |_| .previous,
            .previous => .idle,
            .idle => .idle,
        };
    }

    fn proccessEvent(self: *Self, event: *c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_MOUSE_BUTTON_UP | c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                self.button_state[event.button.button].timestamp = event.button.timestamp;
                self.button_state[event.button.button].is_pressed = event.button.down;
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                const PIXEL_MOVE_AMOUNT = 6.0;
                const mouse_move_state: [2]input.DeviceAxisState = .{
                    .{
                        .value = event.motion.xrel / PIXEL_MOVE_AMOUNT,
                        .timestamp = event.motion.timestamp,
                    },
                    .{
                        .value = event.motion.yrel / PIXEL_MOVE_AMOUNT,
                        .timestamp = event.motion.timestamp,
                    },
                };
                self.axis_state = .{ .active = mouse_move_state };
            },
            else => {},
        }
    }
};
