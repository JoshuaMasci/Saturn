const std = @import("std");
const sdl = @import("zsdl2");
const opengl = @import("zopengl");
const gl = opengl.bindings;

const input = @import("../input.zig");
const App = @import("../app.zig").App;

pub const WindowSize = union(enum) {
    windowed: [2]i32,
    fullscreen,
    maximized,
};

pub const VerticalSync = enum {
    on,
    half,
    off,
};

pub const Platform = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    should_quit: bool,

    mouse: ?Mouse,
    keyboard: ?Keyboard,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const version = sdl.getVersion();
        std.log.info("Starting sdl {}.{}.{}", .{ version.major, version.minor, version.patch });

        try sdl.init(.{
            .events = true,
            .joystick = true,
            .gamecontroller = true,
            .haptic = true,
        });

        var mouse: ?Mouse = null;
        {
            mouse = Mouse.init();
            mouse.?.button_bindings.set(MouseButton.left, .{ .button = .player_interact });

            mouse.?.axis_bindings[0] = .{ .axis = .player_rotate_yaw, .sensitivity = 1.0, .invert = true };
            mouse.?.axis_bindings[1] = .{ .axis = .player_rotate_pitch, .sensitivity = 1.0, .invert = false };
        }

        var keyboard: ?Keyboard = null;
        {
            keyboard = Keyboard.init(allocator);

            // Player Character
            try keyboard.?.button_bindings.put(sdl.Scancode.n, .{ .axis = .{ .axis = .player_rotate_yaw, .dir = .positve } });
            try keyboard.?.button_bindings.put(sdl.Scancode.m, .{ .axis = .{ .axis = .player_rotate_yaw, .dir = .negitive } });

            try keyboard.?.button_bindings.put(sdl.Scancode.w, .{ .axis = .{ .axis = .player_move_forward_backward, .dir = .positve } });
            try keyboard.?.button_bindings.put(sdl.Scancode.s, .{ .axis = .{ .axis = .player_move_forward_backward, .dir = .negitive } });

            try keyboard.?.button_bindings.put(sdl.Scancode.a, .{ .axis = .{ .axis = .player_move_left_right, .dir = .positve } });
            try keyboard.?.button_bindings.put(sdl.Scancode.d, .{ .axis = .{ .axis = .player_move_left_right, .dir = .negitive } });

            try keyboard.?.button_bindings.put(sdl.Scancode.space, .{ .axis = .{ .axis = .player_move_up_down, .dir = .positve } });
            try keyboard.?.button_bindings.put(sdl.Scancode.lshift, .{ .axis = .{ .axis = .player_move_up_down, .dir = .negitive } });

            try keyboard.?.button_bindings.put(sdl.Scancode.e, .{ .button = .player_interact });
        }

        return .{
            .allocator = allocator,
            .should_quit = false,
            .mouse = mouse,
            .keyboard = keyboard,
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.info("Quiting sdl", .{});

        if (self.keyboard) |*keyboard| {
            keyboard.deinit();
        }

        if (self.mouse) |*mouse| {
            mouse.deinit();
        }

        sdl.quit();
    }

    pub fn proccess_events(self: *Self, app: *App) !void {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            switch (event.type) {
                .quit => self.should_quit = true,
                .mousebuttondown, .mousebuttonup => if (self.mouse) |*mouse| {
                    mouse.on_button_event(app, &event.button);
                },
                .mousemotion => if (self.mouse) |*mouse| {
                    mouse.on_move(app, &event.motion);
                },
                .keydown, .keyup => if (self.keyboard) |*keyboard| {

                    //TODO: move capture/free function to app
                    if (event.key.keysym.scancode == .escape and event.key.repeat == 0 and event.key.state == .pressed) {
                        if (self.mouse) |*mouse| {
                            mouse.set_captured(!mouse.is_captured());
                        }
                    }

                    keyboard.on_button_event(app, &event.key);
                },
                else => {},
            }
        }
    }
};

//Taken from SDL3/SDL_mouse.h
const MouseButton = enum(u8) {
    left = 1,
    middle = 2,
    right = 3,
    x1 = 4,
    x2 = 5,
};

const Mouse = struct {
    const Self = @This();

    const ButtonBindingArray = std.EnumArray(MouseButton, ?input.ButtonBinding);
    button_bindings: ButtonBindingArray,
    axis_bindings: [2]?input.AxisBinding = .{ null, null },

    fn init() Self {
        return .{
            .button_bindings = ButtonBindingArray.initFill(null),
        };
    }

    fn deinit(self: *Self) void {
        _ = self;
    }

    fn set_captured(self: Self, captured: bool) void {
        _ = self;
        sdl.setRelativeMouseMode(captured) catch |err| {
            std.log.err("Failed to set relative mouse mode: {}", .{err});
        };
    }

    fn is_captured(self: Self) bool {
        _ = self;
        return sdl.getRelativeMouseMode();
    }

    fn on_button_event(self: *Self, app: *App, event: *sdl.MouseButtonEvent) void {
        if (!self.is_captured()) {
            return;
        }
        const mouse_button = std.meta.intToEnum(MouseButton, event.button) catch {
            std.log.warn("Unknown Mouse Button: {}", .{event.button});
            return;
        };

        if (self.button_bindings.get(mouse_button)) |button_binding| {
            const state: input.ButtonState = switch (event.state) {
                .pressed => .pressed,
                .released => .released,
            };

            switch (button_binding) {
                .button => |button| app.on_button_event(.{
                    .button = button,
                    .state = state,
                }),
                .axis => |value| {
                    app.on_axis_event(.{
                        .axis = value.axis,
                        .value = if (state == .pressed) value.dir.get_value() else 0.0,
                    });
                },
            }
        }
    }

    fn on_move(self: Self, app: *App, event: *sdl.MouseMotionEvent) void {
        if (self.is_captured()) {
            const PIXEL_MOVE_AMOUNT = 6.0;

            if (self.axis_bindings[0]) |*axis_binding| {
                const value = @as(f32, @floatFromInt(event.xrel)) / PIXEL_MOVE_AMOUNT;
                app.on_axis_event(.{ .axis = axis_binding.axis, .value = axis_binding.calc_value(value) });
            }

            if (self.axis_bindings[1]) |*axis_binding| {
                const value = @as(f32, @floatFromInt(event.yrel)) / PIXEL_MOVE_AMOUNT;
                app.on_axis_event(.{ .axis = axis_binding.axis, .value = axis_binding.calc_value(value) });
            }
        }
    }
};

const Keyboard = struct {
    const Self = @This();
    const ButtonBindingArray = std.AutoArrayHashMap(sdl.Scancode, input.ButtonBinding);

    button_bindings: ButtonBindingArray,

    fn init(allocator: std.mem.Allocator) Self {
        return .{
            .button_bindings = ButtonBindingArray.init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.button_bindings.deinit();
    }

    fn on_button_event(self: *Self, app: *App, event: *sdl.KeyboardEvent) void {
        //Don't repeat events
        if (event.repeat != 0) {
            return;
        }

        if (self.button_bindings.get(event.keysym.scancode)) |button_binding| {
            const state: input.ButtonState = switch (event.state) {
                .pressed => .pressed,
                .released => .released,
            };

            switch (button_binding) {
                .button => |button| app.on_button_event(.{
                    .button = button,
                    .state = state,
                }),
                .axis => |value| {
                    app.on_axis_event(.{
                        .axis = value.axis,
                        .value = if (state == .pressed) value.dir.get_value() else 0.0,
                    });
                },
            }
        }
    }
};
