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

        self.keyboard_mouse_device.update();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    self.should_quit = true;
                },
                c.SDL_EVENT_KEY_UP, c.SDL_EVENT_KEY_DOWN => {
                    self.keyboard_mouse_device.proccessKeyboardEvent(&event);
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_WHEEL, c.SDL_EVENT_MOUSE_MOTION => {
                    self.keyboard_mouse_device.proccessMousesEvent(&event);
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
        const keyboard: ?*Keyboard = if (c.SDL_HasKeyboard()) try allocator.create(Keyboard) else null;
        const mouse: ?*Mouse = if (c.SDL_HasMouse()) try allocator.create(Mouse) else null;
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

    fn update(self: *Self) void {
        if (self.keyboard) |keyboard| {
            for (&keyboard.button_state) |*button_state| {
                button_state.previous = button_state.current;
            }
        }

        if (self.mouse) |mouse| {
            mouse.axis_state = .{ .{}, .{} }; //Mouse inputs don't carry over a frame

            for (&mouse.button_state) |*button_state| {
                button_state.previous = button_state.current;
            }
        }
    }

    fn proccessKeyboardEvent(self: *Self, event: *c.SDL_Event) void {
        if (self.keyboard) |keyboard| {
            switch (event.type) {
                c.SDL_EVENT_KEY_UP, c.SDL_EVENT_KEY_DOWN => {
                    keyboard.button_state[event.key.scancode].timestamp = event.key.timestamp;
                    keyboard.button_state[event.key.scancode].current = event.key.down;
                },
                else => {},
            }
        }
    }

    fn proccessMousesEvent(self: *Self, event: *c.SDL_Event) void {
        if (self.mouse) |mouse| {
            switch (event.type) {
                c.SDL_EVENT_MOUSE_BUTTON_UP | c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    mouse.button_state[event.button.button].timestamp = event.button.timestamp;
                    mouse.button_state[event.button.button].current = event.button.down;
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    const PIXEL_MOVE_AMOUNT = 6.0;
                    mouse.axis_state[0].timestamp = event.motion.timestamp;
                    mouse.axis_state[1].timestamp = event.motion.timestamp;
                    mouse.axis_state[0].current = event.motion.xrel / PIXEL_MOVE_AMOUNT;
                    mouse.axis_state[1].current = event.motion.yrel / PIXEL_MOVE_AMOUNT;
                },
                else => {},
            }
        }
    }

    fn getButton(ptr: *anyopaque, context_hash: u32, button: u32) ?input.DeviceButtonState {
        _ = context_hash; // autofix

        const self: *Self = @alignCast(@ptrCast(ptr));
        if (self.keyboard) |keyboard| {
            if (button == 0) {
                return keyboard.button_state[c.SDL_SCANCODE_E];
            }
        }

        return null;
    }

    fn getAxis(ptr: *anyopaque, context_hash: u32, axis: u32) ?input.DeviceAxisState {
        _ = context_hash; // autofix

        const self: *Self = @alignCast(@ptrCast(ptr));
        if (axis == 2) {
            if (self.keyboard) |keyboard| {
                var state: input.DeviceAxisState = .{};

                if (keyboard.button_state[c.SDL_SCANCODE_W].current) {
                    state.current += 1.0;
                    state.timestamp = @max(state.timestamp, keyboard.button_state[c.SDL_SCANCODE_W].timestamp);
                }

                if (keyboard.button_state[c.SDL_SCANCODE_S].current) {
                    state.current -= 1.0;
                    state.timestamp = @max(state.timestamp, keyboard.button_state[c.SDL_SCANCODE_S].timestamp);
                }

                return state;
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

const Keyboard = struct {
    button_state: [c.SDL_SCANCODE_COUNT]input.DeviceButtonState = .{} ** c.SDL_SCANCODE_COUNT,
};

const Mouse = struct {
    button_state: [5]input.DeviceButtonState = .{} ** 5,
    axis_state: [2]input.DeviceAxisState = .{} ** 2,
};
