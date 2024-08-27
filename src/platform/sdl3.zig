const std = @import("std");
const sdl = @import("zsdl3");
const imgui = @import("zimgui");
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
    window: *sdl.Window,
    gl_context: ?sdl.gl.Context,

    mouse: ?Mouse,
    keyboard: ?Keyboard,
    controllers: std.AutoHashMap(sdl.JoystickId, Controller),

    //button_state: std.EnumArray(input.Button, input.ButtonState),
    axis_state: std.EnumArray(input.Axis, input.ButtonAxisState),

    pub fn init_window(allocator: std.mem.Allocator, name: [:0]const u8, size: WindowSize, vsync: VerticalSync) !Self {
        const version = sdl.getVersion();
        std.log.info("Starting sdl {}.{}.{}", .{ version.major, version.minor, version.patch });

        try sdl.init(.{
            .events = true,
            .joystick = true,
            .gamepad = true,
            .haptic = true,
        });

        var window_width: i32 = 0;
        var window_height: i32 = 0;
        var window_maximized = false;
        var window_fullscreen = false;

        switch (size) {
            .windowed => |window_size| {
                window_width = window_size[0];
                window_height = window_size[1];
            },
            .maximized => window_maximized = true,
            .fullscreen => window_fullscreen = true,
        }

        const window = try sdl.Window.create(
            name,
            window_width,
            window_height,
            .{
                .maximized = window_maximized,
                .fullscreen = window_fullscreen,
                .resizable = true,
                .opengl = true,
            },
        );

        const GL_VERSION: [2]u32 = .{ 4, 2 };
        try sdl.gl.setAttribute(sdl.gl.Attr.context_major_version, GL_VERSION[0]);
        try sdl.gl.setAttribute(sdl.gl.Attr.context_minor_version, GL_VERSION[1]);
        try sdl.gl.setAttribute(sdl.gl.Attr.context_profile_mask, @intFromEnum(sdl.gl.Profile.core));
        try sdl.gl.setAttribute(sdl.gl.Attr.doublebuffer, 1);

        const gl_context = try sdl.gl.createContext(window);
        try opengl.loadCoreProfile(&sdl.gl.getProcAddress, GL_VERSION[0], GL_VERSION[1]);

        std.log.info("Opengl Context:\n\tVender: {s}\n\tRenderer: {s}\n\tVersion: {s}\n\tGLSL: {s}", .{
            gl.getString(gl.VENDOR),
            gl.getString(gl.RENDERER),
            gl.getString(gl.VERSION),
            gl.getString(gl.SHADING_LANGUAGE_VERSION),
        });

        try sdl.gl.setSwapInterval(switch (vsync) {
            .on => 1,
            .half => 2,
            .off => 0,
        });

        var mouse: ?Mouse = null;
        if (sdl.hasMouse()) {
            mouse = Mouse.init();
            // mouse.?.button_bindings.set(MouseButton.left, .{ .button = .debug_camera_interact });
            // mouse.?.axis_bindings[0] = .{ .axis = .debug_camera_yaw, .sensitivity = 0.2, .invert = true };
            // mouse.?.axis_bindings[1] = .{ .axis = .debug_camera_pitch, .sensitivity = 0.2, .invert = false };

            mouse.?.axis_bindings[0] = .{ .axis = .player_rotate_yaw, .sensitivity = 0.2, .invert = true };
            mouse.?.axis_bindings[1] = .{ .axis = .player_rotate_pitch, .sensitivity = 0.2, .invert = false };
        }

        var keyboard: ?Keyboard = null;
        if (sdl.hasKeyboard()) {
            keyboard = Keyboard.init(allocator);

            // Debug Camera
            // try keyboard.?.button_bindings.put(sdl.Scancode.a, .{ .axis = .{ .axis = .debug_camera_left_right, .dir = .positve } });
            // try keyboard.?.button_bindings.put(sdl.Scancode.d, .{ .axis = .{ .axis = .debug_camera_left_right, .dir = .negitive } });

            // try keyboard.?.button_bindings.put(sdl.Scancode.space, .{ .axis = .{ .axis = .debug_camera_up_down, .dir = .positve } });
            // try keyboard.?.button_bindings.put(sdl.Scancode.lshift, .{ .axis = .{ .axis = .debug_camera_up_down, .dir = .negitive } });

            // try keyboard.?.button_bindings.put(sdl.Scancode.w, .{ .axis = .{ .axis = .debug_camera_forward_backward, .dir = .positve } });
            // try keyboard.?.button_bindings.put(sdl.Scancode.s, .{ .axis = .{ .axis = .debug_camera_forward_backward, .dir = .negitive } });

            // try keyboard.?.button_bindings.put(sdl.Scancode.q, .{ .button = .debug_camera_fast_move });

            // Player Character
            try keyboard.?.button_bindings.put(sdl.Scancode.n, .{ .axis = .{ .axis = .player_rotate_yaw, .dir = .positve } });
            try keyboard.?.button_bindings.put(sdl.Scancode.m, .{ .axis = .{ .axis = .player_rotate_yaw, .dir = .negitive } });

            try keyboard.?.button_bindings.put(sdl.Scancode.w, .{ .axis = .{ .axis = .player_move_forward_backward, .dir = .positve } });
            try keyboard.?.button_bindings.put(sdl.Scancode.s, .{ .axis = .{ .axis = .player_move_forward_backward, .dir = .negitive } });

            try keyboard.?.button_bindings.put(sdl.Scancode.a, .{ .axis = .{ .axis = .player_move_left_right, .dir = .positve } });
            try keyboard.?.button_bindings.put(sdl.Scancode.d, .{ .axis = .{ .axis = .player_move_left_right, .dir = .negitive } });

            try keyboard.?.button_bindings.put(sdl.Scancode.space, .{ .button = .player_move_jump });
        }

        imgui.init(allocator);
        imgui.io.setConfigFlags(.{
            .dock_enable = true,
            .nav_enable_keyboard = true,
            .nav_enable_gamepad = false,
        });
        imgui.backend.init(window, gl_context);

        const controllers = std.AutoHashMap(sdl.JoystickId, Controller).init(allocator);

        return .{
            .allocator = allocator,
            .should_quit = false,
            .window = window,
            .gl_context = gl_context,
            .mouse = mouse,
            .keyboard = keyboard,
            .controllers = controllers,

            .axis_state = std.EnumArray(input.Axis, input.ButtonAxisState).initFill(.{}),
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.info("Shutting down sdl", .{});

        var it = self.controllers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.controllers.deinit();

        if (self.keyboard) |*keyboard| {
            keyboard.deinit();
        }

        if (self.mouse) |*mouse| {
            mouse.deinit();
        }

        imgui.backend.deinit();
        imgui.deinit();

        if (self.gl_context) |gl_context| {
            sdl.gl.deleteContext(gl_context);
        }
        sdl.Window.destroy(self.window);
        sdl.quit();
    }

    pub fn get_window_size(self: Self) ![2]u32 {
        var width: i32 = 0;
        var height: i32 = 0;
        try sdl.Window.getSize(self.window, &width, &height);
        return .{ @intCast(width), @intCast(height) };
    }

    pub fn gl_swap_window(self: Self) void {
        sdl.gl.swapWindow(self.window) catch |err| std.log.err("glSwapWindow Error: {}", .{err});
    }

    pub fn proccess_events(self: *Self, app: *App) !void {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            _ = imgui.backend.processEvent(&event);

            switch (event.type) {
                .quit => self.should_quit = true,
                .mouse_button_down, .mouse_button_up => if (self.mouse) |*mouse| {
                    mouse.on_button_event(app, &event.button);
                },
                .mouse_motion => if (self.mouse) |*mouse| {
                    mouse.on_move(app, &event.motion);
                },
                .key_down, .key_up => if (self.keyboard) |*keyboard| {

                    //TODO: move capture/free function to app
                    if (event.key.keysym.scancode == .escape and event.key.repeat == 0 and event.key.state == .pressed) {
                        if (self.mouse) |*mouse| {
                            mouse.set_captured(!mouse.is_captured());
                        }
                    }

                    keyboard.on_button_event(app, &event.key);
                },
                .gamepad_added => {
                    const controller = Controller.init(self.allocator, event.gdevice.which);
                    try self.controllers.put(controller.id, controller);
                },
                .gamepad_removed => {
                    if (self.controllers.fetchRemove(event.gdevice.which)) |entry| {
                        var controller = entry.value;
                        controller.deinit();
                    }
                },
                .gamepad_button_down, .gamepad_button_up => {
                    if (self.controllers.getPtr(event.gbutton.which)) |controller| {
                        controller.on_button_event(app, &event.gbutton);
                    }
                },
                .gamepad_axis_motion => {
                    if (self.controllers.getPtr(event.gbutton.which)) |controller| {
                        controller.on_axis_event(app, &event.gaxis);
                    }
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
    //const ButtonAxisStateArray = std.EnumArray(input.Axis, input.ButtonAxisState);

    button_bindings: ButtonBindingArray,
    //axis_state: ButtonAxisStateArray,

    axis_bindings: [2]?input.AxisBinding = .{ null, null },

    fn init() Self {
        return .{
            .button_bindings = ButtonBindingArray.initFill(null),
            //.axis_state = ButtonAxisStateArray.initFill(input.ButtonAxisState.Default),
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
                    //var axis_state = self.axis_state.getPtr(value.axis);
                    //axis_state.update(value.dir, state);

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
            if (self.axis_bindings[0]) |*axis_binding| {
                app.on_axis_event(.{ .axis = axis_binding.axis, .value = axis_binding.calc_value(event.xrel) });
            }

            if (self.axis_bindings[1]) |*axis_binding| {
                app.on_axis_event(.{ .axis = axis_binding.axis, .value = axis_binding.calc_value(event.yrel) });
            }
        }
    }
};

const Keyboard = struct {
    const Self = @This();
    const ButtonBindingArray = std.AutoArrayHashMap(sdl.Scancode, input.ButtonBinding);
    //const ButtonAxisStateArray = std.EnumArray(input.Axis, input.ButtonAxisState);

    button_bindings: ButtonBindingArray,
    //axis_state: ButtonAxisStateArray,

    fn init(allocator: std.mem.Allocator) Self {
        return .{
            .button_bindings = ButtonBindingArray.init(allocator),
            //.axis_state = ButtonAxisStateArray.initFill(input.ButtonAxisState.Default),
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
                    // var axis_state = self.axis_state.getPtr(value.axis);
                    // axis_state.update(value.dir, state);

                    app.on_axis_event(.{
                        .axis = value.axis,
                        .value = if (state == .pressed) value.dir.get_value() else 0.0,
                    });
                },
            }
        }
    }
};

const Controller = struct {
    const Self = @This();
    const ButtonBindingArray = std.AutoArrayHashMap(sdl.Gamepad.Button, input.ButtonBinding);
    //const ButtonAxisStateArray = std.EnumArray(input.Axis, input.ButtonAxisState);
    const AxisBindingArray = std.AutoArrayHashMap(sdl.Gamepad.Axis, input.AxisBinding);

    id: sdl.JoystickId,
    gamepad: *sdl.Gamepad,

    button_bindings: ButtonBindingArray,
    //axis_state: ButtonAxisStateArray,
    axis_bindings: AxisBindingArray,

    fn init(allocator: std.mem.Allocator, id: sdl.JoystickId) Self {
        const gamepad = sdl.Gamepad.open(id).?;
        const name_slice = gamepad.getName();
        std.log.info("Gamepad: {s}", .{name_slice});

        gamepad.setLed(.{ 0, 255, 255 });

        var button_bindings = ButtonBindingArray.init(allocator);
        button_bindings.put(.south, .{ .button = .player_move_jump }) catch unreachable;

        var axis_bindings = AxisBindingArray.init(allocator);
        axis_bindings.put(.left_x, .{ .axis = .player_move_left_right }) catch unreachable;
        axis_bindings.put(.left_y, .{ .axis = .player_move_forward_backward }) catch unreachable;
        axis_bindings.put(.right_x, .{ .axis = .player_rotate_yaw }) catch unreachable;
        axis_bindings.put(.right_y, .{ .axis = .player_rotate_pitch }) catch unreachable;

        return .{
            .id = id,
            .gamepad = gamepad,
            .button_bindings = button_bindings,
            //.axis_state = ButtonAxisStateArray.initFill(input.ButtonAxisState.Default),
            .axis_bindings = axis_bindings,
        };
    }

    fn deinit(self: *Self) void {
        self.gamepad.close();
        self.button_bindings.deinit();
        self.axis_bindings.deinit();
    }

    fn on_button_event(self: *Self, app: *App, event: *sdl.GamepadButtonEvent) void {
        const gamepad_button = std.meta.intToEnum(sdl.Gamepad.Button, event.button) catch {
            std.log.warn("Unknown Gamepad Button: {}", .{event.button});
            return;
        };

        if (self.button_bindings.get(gamepad_button)) |button_binding| {
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
                    // var axis_state = self.axis_state.getPtr(value.axis);
                    // axis_state.update(value.dir, state);

                    app.on_axis_event(.{
                        .axis = value.axis,
                        .value = if (state == .pressed) value.dir.get_value() else 0.0,
                    });
                },
            }
        }
    }

    fn on_axis_event(self: *Self, app: *App, event: *sdl.GamepadAxisEvent) void {
        const gamepad_axis = std.meta.intToEnum(sdl.Gamepad.Axis, event.axis) catch {
            std.log.warn("Unknown Gamepad Axis: {}", .{event.axis});
            return;
        };

        if (self.axis_bindings.get(gamepad_axis)) |binding| {
            const value = @as(f32, @floatFromInt(event.value)) / @as(f32, @floatFromInt(std.math.maxInt(i16)));
            app.on_axis_event(.{ .axis = binding.axis, .value = binding.calc_value(value) });
        }
    }
};
