const std = @import("std");

const c = @import("../c.zig");

const input = @import("../input.zig");
const StringHash = @import("../string_hash.zig");
const App = @import("../app.zig").App;

pub const WindowSize = union(enum) {
    windowed: [2]i32,
    fullscreen,
    maximized,
};

pub const Platform = struct {
    const Self = @This();

    should_quit: bool,

    window: *c.SDL_Window,
    gl_context: ?c.SDL_GLContext,

    mouse: ?Mouse,
    keyboard: ?Keyboard,

    pub fn init_window(allocator: std.mem.Allocator, name: [:0]const u8, size: WindowSize) !Self {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            std.debug.panic("SDL ERROR {s}", .{c.SDL_GetError()});
        }

        var window_width: i32 = 0;
        var window_height: i32 = 0;
        var window_flags: u32 = c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_OPENGL;
        switch (size) {
            .windowed => |window_size| {
                window_width = window_size[0];
                window_height = window_size[1];
            },
            .maximized => window_flags |= c.SDL_WINDOW_MAXIMIZED,
            .fullscreen => window_flags |= c.SDL_WINDOW_FULLSCREEN,
        }

        var window: *c.SDL_Window = undefined;
        if (c.SDL_CreateWindow(name, window_width, window_height, window_flags)) |valid_window| {
            window = valid_window;
        } else {
            std.debug.panic("SDL WINDOW ERROR {s}", .{c.SDL_GetError()});
        }

        // try sdl.gl.setAttribute(sdl.gl.Attr.doublebuffer, 1);
        // try sdl.gl.setAttribute(sdl.gl.Attr.context_major_version, 4);
        // try sdl.gl.setAttribute(sdl.gl.Attr.context_minor_version, 6);
        // try sdl.gl.setAttribute(sdl.gl.Attr.context_profile_mask, @intFromEnum(sdl.gl.Profile.core));

        const gl_context: c.SDL_GLContext = c.SDL_GL_CreateContext(window);

        _ = c.gladLoadGLLoader(@ptrCast(&c.SDL_GL_GetProcAddress));

        std.log.info("Opengl Context:\n\tVender: {s}\n\tRenderer: {s}\n\tVersion: {s}\n\tGLSL: {s}", .{
            c.glGetString(c.GL_VENDOR),
            c.glGetString(c.GL_RENDERER),
            c.glGetString(c.GL_VERSION),
            c.glGetString(c.GL_SHADING_LANGUAGE_VERSION),
        });

        if (c.SDL_GL_SetSwapInterval(1) != 0) {
            std.log.err("SDL VSYNC ERROR {s}", .{c.SDL_GetError()});
        }

        var mouse = Mouse.init();
        var keyboard = Keyboard.init(allocator);
        {
            mouse.button_bindings.set(MouseButton.left, .{ .button = .debug_camera_interact });

            try keyboard.button_bindings.put(c.SDL_SCANCODE_A, .{ .axis = .{ .axis = .debug_camera_left_right, .dir = .positve } });
            try keyboard.button_bindings.put(c.SDL_SCANCODE_D, .{ .axis = .{ .axis = .debug_camera_left_right, .dir = .negitive } });

            try keyboard.button_bindings.put(c.SDL_SCANCODE_SPACE, .{ .axis = .{ .axis = .debug_camera_up_down, .dir = .positve } });
            try keyboard.button_bindings.put(c.SDL_SCANCODE_LSHIFT, .{ .axis = .{ .axis = .debug_camera_up_down, .dir = .negitive } });

            try keyboard.button_bindings.put(c.SDL_SCANCODE_W, .{ .axis = .{ .axis = .debug_camera_forward_backward, .dir = .positve } });
            try keyboard.button_bindings.put(c.SDL_SCANCODE_S, .{ .axis = .{ .axis = .debug_camera_forward_backward, .dir = .negitive } });
        }

        return .{
            .should_quit = false,
            .window = window,
            .gl_context = gl_context,
            .mouse = mouse,
            .keyboard = keyboard,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.keyboard) |*keyboard| {
            keyboard.deinit();
        }

        if (self.mouse) |*mouse| {
            mouse.deinit();
        }

        if (self.gl_context) |gl_context| {
            _ = c.SDL_GL_DeleteContext(gl_context);
        }
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    pub fn get_window_size(self: Self) ![2]i32 {
        var width: i32 = 0;
        var height: i32 = 0;
        if (c.SDL_GetWindowSize(self.window, &width, &height) != 0) {
            std.log.err("SDL WINDOW ERROR {s}", .{c.SDL_GetError()});
        }
        return .{ width, height };
    }

    pub fn gl_swap_window(self: Self) void {
        if (c.SDL_GL_SwapWindow(self.window) != 0) {
            std.log.err("SDL GL ERROR {s}", .{c.SDL_GetError()});
        }
    }

    //TODO: make an abstract version of event handler function
    pub fn proccess_events(self: *Self, app: *App) void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) == c.SDL_TRUE) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => self.should_quit = true,
                c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => self.proccess_mouse_button_event(app, &event.button),
                c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => self.proccess_keyboard_event(app, &event.key),
                else => {},
            }
        }
    }

    fn proccess_mouse_button_event(self: *Self, app: *App, event: *c.SDL_MouseButtonEvent) void {
        if (self.mouse) |*mouse| {
            mouse.on_button_event(app, event);
        }
    }

    fn proccess_keyboard_event(self: *Self, app: *App, event: *c.SDL_KeyboardEvent) void {
        if (event.keysym.scancode == c.SDL_SCANCODE_ESCAPE and event.state != 0) {
            self.should_quit = true;
        }

        if (self.keyboard) |*keyboard| {
            if (event.repeat == 0) {
                keyboard.on_button_event(app, event);
            }
        }
    }
};

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
    const ButtonAxisStateArray = std.EnumArray(input.Axis, input.ButtonAxisState);

    captured: bool,
    button_bindings: ButtonBindingArray,
    axis_state: ButtonAxisStateArray,

    fn init() Self {
        return .{
            .captured = false,
            .button_bindings = ButtonBindingArray.initFill(null),
            .axis_state = ButtonAxisStateArray.initFill(input.ButtonAxisState.Default),
        };
    }

    fn deinit(self: *Self) void {
        _ = self;
    }

    fn on_button_event(self: *Self, app: *App, event: *c.SDL_MouseButtonEvent) void {
        if (event.button > @intFromEnum(MouseButton.x2)) {
            std.log.warn("Mouse Button outside of allowed range {}, TODO allow larger value", .{event.button});
            return;
        }

        const mouse_button: MouseButton = @enumFromInt(event.button);

        if (self.button_bindings.get(mouse_button)) |button_binding| {
            var state: input.ButtonState = .released;
            if (event.state == 1) {
                state = .pressed;
            }

            switch (button_binding) {
                .button => |button| app.on_button_event(.{
                    .button = button,
                    .state = state,
                }),
                .axis => |value| {
                    var axis_state = self.axis_state.getPtr(value.axis);
                    axis_state.update(value.dir, state);

                    app.on_axis_event(.{
                        .axis = value.axis,
                        .value = axis_state.get_value(),
                    });
                },
            }
        }
    }
};

const Keyboard = struct {
    const Self = @This();
    const ButtonBindingMap = std.AutoHashMap(c.SDL_Scancode, input.ButtonBinding);
    const ButtonAxisStateArray = std.EnumArray(input.Axis, input.ButtonAxisState);

    allocator: std.mem.Allocator,
    button_bindings: ButtonBindingMap,
    axis_state: ButtonAxisStateArray,

    fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .button_bindings = ButtonBindingMap.init(allocator),
            .axis_state = ButtonAxisStateArray.initFill(input.ButtonAxisState.Default),
        };
    }

    fn deinit(self: *Self) void {
        self.button_bindings.deinit();
    }

    fn on_button_event(self: *Self, app: *App, event: *c.SDL_KeyboardEvent) void {
        if (self.button_bindings.get(event.keysym.scancode)) |button_binding| {
            var state: input.ButtonState = .released;
            if (event.state == 1) {
                state = .pressed;
            }

            switch (button_binding) {
                .button => |button| app.on_button_event(.{
                    .button = button,
                    .state = state,
                }),
                .axis => |value| {
                    var axis_state = self.axis_state.getPtr(value.axis);
                    axis_state.update(value.dir, state);

                    app.on_axis_event(.{
                        .axis = value.axis,
                        .value = axis_state.get_value(),
                    });
                },
            }
        }
    }
};
