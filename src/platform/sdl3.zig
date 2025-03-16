const std = @import("std");

const input = @import("../input.zig");
const App = @import("../app.zig").App;

const Settings = @import("../rendering/settings.zig");

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
        input_devices.appendAssumeCapacity(keyboard_mouse_device.getInputDevice());

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

    pub fn createWindow(self: *Self, name: [:0]const u8, size: Settings.WindowSize) Window {
        _ = self; // autofix
        var window_width: i32 = 0;
        var window_height: i32 = 0;
        var window_flags = c.SDL_WINDOW_RESIZABLE;

        switch (size) {
            .windowed => |window_size| {
                window_width = window_size[0];
                window_height = window_size[1];
            },
            .maximized => window_flags |= c.SDL_WINDOW_MAXIMIZED,
            .fullscreen => window_flags |= c.SDL_WINDOW_FULLSCREEN,
        }

        const handle = c.SDL_CreateWindow(name, window_width, window_height, window_flags).?;
        return .{ .handle = handle };
    }

    pub fn destroyWindow(self: *Self, window: Window) void {
        _ = self; // autofix
        _ = c.SDL_DestroyWindowSurface(window.handle);
    }

    pub fn captureMouse(self: *Self, window: Window) void {
        if (self.keyboard_mouse_device.mouse) |mouse| {
            mouse.capture(window);
        }
    }

    pub fn releaseMouse(self: *Self) void {
        if (self.keyboard_mouse_device.mouse) |mouse| {
            mouse.release();
        }
    }

    pub fn isMouseCaptured(self: *Self) bool {
        if (self.keyboard_mouse_device.mouse) |mouse| {
            return mouse.isCaptured();
        }
        return false;
    }

    pub fn proccessEvents(self: *Self) !void {
        self.keyboard_mouse_device.beginFrame();

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {

            //TODO: only update when input is in "Menu" mode, aka mouse not captured
            _ = @import("zimgui").backend.processEvent(&event);
            switch (event.type) {
                c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    self.should_quit = true;
                },
                c.SDL_EVENT_KEY_UP, c.SDL_EVENT_KEY_DOWN => {
                    // Releases mouse so it can't ever get stuck
                    if (event.key.scancode == c.SDL_SCANCODE_ESCAPE and event.key.down) {
                        self.releaseMouse();
                    }

                    if (self.keyboard_mouse_device.keyboard) |keyboard| {
                        keyboard.proccessEvent(&event);
                    }
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_WHEEL, c.SDL_EVENT_MOUSE_MOTION => {
                    if (self.keyboard_mouse_device.mouse) |mouse| {
                        mouse.proccessEvent(&event);
                    }
                },
                c.SDL_EVENT_GAMEPAD_ADDED => {
                    const gamepad = c.SDL_OpenGamepad(event.gdevice.which).?;
                    const name = c.SDL_GetGamepadName(gamepad);
                    std.log.info("Gamepad Added: {s}({})", .{ name, event.gdevice.which });
                },
                c.SDL_EVENT_GAMEPAD_REMOVED => {
                    const gamepad = c.SDL_GetGamepadFromID(event.gdevice.which);
                    const name = c.SDL_GetGamepadName(gamepad);
                    std.log.info("Gamepad Removed: {s}({})", .{ name, event.gdevice.which });
                    c.SDL_CloseGamepad(gamepad);
                },
                else => {},
            }
        }
    }

    pub fn getInputDevices(self: Self) []const input.InputDevice {
        return self.input_devices.items;
    }
};

pub const Window = struct {
    handle: *c.SDL_Window,

    pub fn getSize(self: @This()) [2]u32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSize(self.handle, &w, &h);
        return .{ @intCast(w), @intCast(h) };
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
        const self: *Self = @alignCast(@ptrCast(ptr));

        if (self.keyboard) |keyboard| {
            if (Keyboard.getButton(keyboard, context_hash, button)) |state| {
                return state;
            }
        }

        if (self.keyboard) |mouse| {
            if (Mouse.getButton(mouse, context_hash, button)) |state| {
                return state;
            }
        }

        return null;
    }

    fn getAxis(ptr: *anyopaque, context_hash: u32, axis: u32) ?input.DeviceAxisState {
        const self: *Self = @alignCast(@ptrCast(ptr));

        if (self.keyboard) |keyboard| {
            if (Keyboard.getAxis(keyboard, context_hash, axis)) |state| {
                return state;
            }
        }

        if (self.mouse) |mouse| {
            if (Mouse.getAxis(mouse, context_hash, axis)) |state| {
                return state;
            }
        }

        return null;
    }

    pub fn getInputDevice(self: *Self) input.InputDevice {
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

    fn getButton(ptr: *anyopaque, context_hash: u32, button: u32) ?input.DeviceButtonState {
        _ = context_hash; // autofix

        const self: *Self = @alignCast(@ptrCast(ptr));
        if (button == 0) {
            return self.button_state[c.SDL_SCANCODE_E].toDeviceState();
        }

        return null;
    }

    fn getAxis(ptr: *anyopaque, context_hash: u32, axis: u32) ?input.DeviceAxisState {
        _ = context_hash; // autofix

        const self: *Self = @alignCast(@ptrCast(ptr));

        switch (axis) {
            0 => return self.tempKeyAxis(c.SDL_SCANCODE_A, c.SDL_SCANCODE_D),
            1 => return self.tempKeyAxis(c.SDL_SCANCODE_SPACE, c.SDL_SCANCODE_LSHIFT),
            2 => return self.tempKeyAxis(c.SDL_SCANCODE_W, c.SDL_SCANCODE_S),
            else => {},
        }

        return null;
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

    captured_window: ?Window = null,

    fn isCaptured(self: *Self) bool {
        if (self.captured_window) |window| {
            if (c.SDL_GetWindowRelativeMouseMode(window.handle)) {
                return true;
            }
            self.captured_window = null;
        }

        return false;
    }

    fn capture(self: *Self, window: Window) void {
        if (c.SDL_SetWindowRelativeMouseMode(window.handle, true) == true) {
            self.captured_window = window;
        }
    }

    fn release(self: *Self) void {
        if (self.captured_window) |window| {
            _ = c.SDL_SetWindowRelativeMouseMode(window.handle, false);
            self.captured_window = null;
        }
    }

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
                const PIXEL_MOVE_AMOUNT = 25.0; //TODO: is this even needed since the xrel is already a float?
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

    fn getButton(ptr: *anyopaque, context_hash: u32, button: u32) ?input.DeviceButtonState {
        _ = ptr; // autofix
        _ = context_hash; // autofix
        _ = button; // autofix
        return null;
    }

    fn getAxis(ptr: *anyopaque, context_hash: u32, axis: u32) ?input.DeviceAxisState {
        _ = context_hash; // autofix
        const self: *Self = @alignCast(@ptrCast(ptr));

        if (axis == 3 or axis == 4) {
            switch (self.axis_state) {
                .active => |axes| {
                    if (self.isCaptured()) {
                        if (axis == 3) {
                            var state = axes[0];
                            state.value *= -1.0;
                            return state;
                        } else {
                            return axes[1];
                        }
                    }
                },
                .previous => return .{}, //Should still return the empty movement if the mouse is uncaptured
                .idle => {},
            }
        }

        return null;
    }
};
