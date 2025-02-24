const std = @import("std");

const input = @import("../input2.zig");
const StringHash = @import("../string_hash.zig");

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

    pub fn init(allocator: std.mem.Allocator) !Self {
        const version = c.SDL_GetVersion();
        std.log.info("Starting sdl {}.{}.{}", .{ c.SDL_VERSIONNUM_MAJOR(version), c.SDL_VERSIONNUM_MINOR(version), c.SDL_VERSIONNUM_MICRO(version) });

        if (!c.SDL_Init(c.SDL_INIT_EVENTS | c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD | c.SDL_INIT_HAPTIC)) {
            return error.sdlInitFailed;
        }

        const keyboard_mouse_device = try allocator.create(KeyboardMouse);
        keyboard_mouse_device.* = try KeyboardMouse.init(allocator);

        return .{
            .allocator = allocator,
            .should_quit = false,
            .keyboard_mouse_device = keyboard_mouse_device,
        };
    }

    pub fn deinit(self: *Self) void {
        self.keyboard_mouse_device.deinit();
        self.allocator.destroy(self.keyboard_mouse_device);

        std.log.info("Quiting sdl", .{});
        c.SDL_Quit();
    }

    pub fn proccess_events(self: *Self, app: *App) !void {
        _ = app; // autofix

        self.keyboard_mouse_device.clearInputs();

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

    fn clearInputs(self: *Self) void {
        if (self.mouse) |mouse| {
            mouse.axis_state = .{ 0.0, 0.0 };
        }
    }

    fn proccessKeyboardEvent(self: *Self, event: *c.SDL_Event) void {
        if (self.keyboard) |keyboard| {
            switch (event.type) {
                c.SDL_EVENT_KEY_UP, c.SDL_EVENT_KEY_DOWN => {
                    keyboard.button_state[event.key.scancode] = event.key.down;
                },
                else => {},
            }
        }
    }

    fn proccessMousesEvent(self: *Self, event: *c.SDL_Event) void {
        if (self.mouse) |mouse| {
            switch (event.type) {
                c.SDL_EVENT_MOUSE_BUTTON_UP | c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    mouse.button_state[event.button.button] = event.button.down;
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    const PIXEL_MOVE_AMOUNT = 6.0;
                    mouse.axis_state[0] = event.motion.xrel / PIXEL_MOVE_AMOUNT;
                    mouse.axis_state[1] = event.motion.yrel / PIXEL_MOVE_AMOUNT;
                },
                else => {},
            }
        }
    }

    fn getButton(ptr: *anyopaque, context: StringHash, button: StringHash) ?bool {
        _ = ptr; // autofix
        _ = context; // autofix
        _ = button; // autofix
        return null;
    }

    fn getAxis(ptr: *anyopaque, context: StringHash, axis: StringHash) ?f32 {
        _ = ptr; // autofix
        _ = context; // autofix
        _ = axis; // autofix
        return null;
    }

    pub fn getInputDevice(self: *Self) input.InputDevice {
        return .{
            .ptr = @ptrCast(self),
            .get_button = &Self.getButton,
            .get_axis = &Self.getAxis,
        };
    }
};

const Keyboard = struct {
    button_state: [c.SDL_SCANCODE_COUNT]bool = .{false} ** c.SDL_SCANCODE_COUNT,
};

const Mouse = struct {
    button_state: [5]bool = .{false} ** 5,
    axis_state: [2]f32 = .{0.0} ** 2,
};
