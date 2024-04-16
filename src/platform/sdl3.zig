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
        _ = allocator;

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
        var keyboard = Keyboard.init();
        {
            mouse.button_bindings.set(MouseButton.left, .{ .button = .debug_camera_interact });

            keyboard.button_bindings.set(Scancode.a, .{ .axis = .{ .axis = .debug_camera_left_right, .dir = .positve } });
            keyboard.button_bindings.set(Scancode.d, .{ .axis = .{ .axis = .debug_camera_left_right, .dir = .negitive } });

            keyboard.button_bindings.set(Scancode.space, .{ .axis = .{ .axis = .debug_camera_up_down, .dir = .positve } });
            keyboard.button_bindings.set(Scancode.lshift, .{ .axis = .{ .axis = .debug_camera_up_down, .dir = .negitive } });

            keyboard.button_bindings.set(Scancode.w, .{ .axis = .{ .axis = .debug_camera_forward_backward, .dir = .positve } });
            keyboard.button_bindings.set(Scancode.s, .{ .axis = .{ .axis = .debug_camera_forward_backward, .dir = .negitive } });
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

    //TODO: make an abstract version of app event handler function
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

//Ported from SDL3/SDL_mouse.h
//TODO: keep up to date with new buttons
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
        const mouse_button = std.meta.intToEnum(MouseButton, event.button) catch {
            std.log.warn("Unknown Mouse Button: {}", .{event.button});
            return;
        };

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
    const ButtonBindingArray = std.EnumArray(Scancode, ?input.ButtonBinding);
    const ButtonAxisStateArray = std.EnumArray(input.Axis, input.ButtonAxisState);

    button_bindings: ButtonBindingArray,
    axis_state: ButtonAxisStateArray,

    fn init() Self {
        return .{
            .button_bindings = ButtonBindingArray.initFill(null),
            .axis_state = ButtonAxisStateArray.initFill(input.ButtonAxisState.Default),
        };
    }

    fn deinit(self: *Self) void {
        _ = self;
    }

    fn on_button_event(self: *Self, app: *App, event: *c.SDL_KeyboardEvent) void {
        const scancode = std.meta.intToEnum(Scancode, event.keysym.scancode) catch {
            std.log.warn("Unknown Scancode: {}", .{event.keysym.scancode});
            return;
        };

        if (self.button_bindings.get(scancode)) |button_binding| {
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

//Ported from SDL3/SDL_scancode.h
//TODO: keep up to date with new keys
const Scancode = enum(u32) {
    //Don't need unknown since it will be caught by the int -> enum check
    //unknown = 0,

    a = 4,
    b = 5,
    c = 6,
    d = 7,
    e = 8,
    f = 9,
    g = 10,
    h = 11,
    i = 12,
    j = 13,
    k = 14,
    l = 15,
    m = 16,
    n = 17,
    o = 18,
    p = 19,
    q = 20,
    r = 21,
    s = 22,
    t = 23,
    u = 24,
    v = 25,
    w = 26,
    x = 27,
    y = 28,
    z = 29,

    @"1" = 30,
    @"2" = 31,
    @"3" = 32,
    @"4" = 33,
    @"5" = 34,
    @"6" = 35,
    @"7" = 36,
    @"8" = 37,
    @"9" = 38,
    @"0" = 39,

    @"return" = 40,
    escape = 41,
    backspace = 42,
    tab = 43,
    space = 44,

    minus = 45,
    equals = 46,
    leftbracket = 47,
    rightbracket = 48,
    backslash = 49,
    nonushash = 50,
    semicolon = 51,
    apostrophe = 52,
    grave = 53,
    comma = 54,
    period = 55,
    slash = 56,

    capslock = 57,

    f1 = 58,
    f2 = 59,
    f3 = 60,
    f4 = 61,
    f5 = 62,
    f6 = 63,
    f7 = 64,
    f8 = 65,
    f9 = 66,
    f10 = 67,
    f11 = 68,
    f12 = 69,

    printscreen = 70,
    scrolllock = 71,
    pause = 72,
    insert = 73,
    home = 74,
    pageup = 75,
    delete = 76,
    end = 77,
    pagedown = 78,
    right = 79,
    left = 80,
    down = 81,
    up = 82,

    numlockclear = 83,
    kp_divide = 84,
    kp_multiply = 85,
    kp_minus = 86,
    kp_plus = 87,
    kp_enter = 88,
    kp_1 = 89,
    kp_2 = 90,
    kp_3 = 91,
    kp_4 = 92,
    kp_5 = 93,
    kp_6 = 94,
    kp_7 = 95,
    kp_8 = 96,
    kp_9 = 97,
    kp_0 = 98,
    kp_period = 99,

    nonusbackslash = 100,
    application = 101,
    power = 102,
    kp_equals = 103,
    f13 = 104,
    f14 = 105,
    f15 = 106,
    f16 = 107,
    f17 = 108,
    f18 = 109,
    f19 = 110,
    f20 = 111,
    f21 = 112,
    f22 = 113,
    f23 = 114,
    f24 = 115,
    execute = 116,
    help = 117,
    menu = 118,
    select = 119,
    stop = 120,
    again = 121,
    undo = 122,
    cut = 123,
    copy = 124,
    paste = 125,
    find = 126,
    mute = 127,
    volumeup = 128,
    volumedown = 129,
    kp_comma = 133,
    kp_equalsas400 = 134,

    international1 = 135,
    international2 = 136,
    international3 = 137,
    international4 = 138,
    international5 = 139,
    international6 = 140,
    international7 = 141,
    international8 = 142,
    international9 = 143,
    lang1 = 144,
    lang2 = 145,
    lang3 = 146,
    lang4 = 147,
    lang5 = 148,
    lang6 = 149,
    lang7 = 150,
    lang8 = 151,
    lang9 = 152,

    alterase = 153,
    sysreq = 154,
    cancel = 155,
    clear = 156,
    prior = 157,
    return2 = 158,
    separator = 159,
    out = 160,
    oper = 161,
    clearagain = 162,
    crsel = 163,
    exsel = 164,

    kp_00 = 176,
    kp_000 = 177,
    thousandsseparator = 178,
    decimalseparator = 179,
    currencyunit = 180,
    currencysubunit = 181,
    kp_leftparen = 182,
    kp_rightparen = 183,
    kp_leftbrace = 184,
    kp_rightbrace = 185,
    kp_tab = 186,
    kp_backspace = 187,
    kp_a = 188,
    kp_b = 189,
    kp_c = 190,
    kp_d = 191,
    kp_e = 192,
    kp_f = 193,
    kp_xor = 194,
    kp_power = 195,
    kp_percent = 196,
    kp_less = 197,
    kp_greater = 198,
    kp_ampersand = 199,
    kp_dblampersand = 200,
    kp_verticalbar = 201,
    kp_dblverticalbar = 202,
    kp_colon = 203,
    kp_hash = 204,
    kp_space = 205,
    kp_at = 206,
    kp_exclam = 207,
    kp_memstore = 208,
    kp_memrecall = 209,
    kp_memclear = 210,
    kp_memadd = 211,
    kp_memsubtract = 212,
    kp_memmultiply = 213,
    kp_memdivide = 214,
    kp_plusminus = 215,
    kp_clear = 216,
    kp_clearentry = 217,
    kp_binary = 218,
    kp_octal = 219,
    kp_decimal = 220,
    kp_hexadecimal = 221,

    lctrl = 224,
    lshift = 225,
    lalt = 226,
    lgui = 227,
    rctrl = 228,
    rshift = 229,
    ralt = 230,
    rgui = 231,

    mode = 257,

    audionext = 258,
    audioprev = 259,
    audiostop = 260,
    audioplay = 261,
    audiomute = 262,
    mediaselect = 263,
    www = 264,
    mail = 265,
    calculator = 266,
    computer = 267,
    ac_search = 268,
    ac_home = 269,
    ac_back = 270,
    ac_forward = 271,
    ac_stop = 272,
    ac_refresh = 273,
    ac_bookmarks = 274,

    brightnessdown = 275,
    brightnessup = 276,
    displayswitch = 277,
    kbdillumtoggle = 278,
    kbdillumdown = 279,
    kbdillumup = 280,
    eject = 281,
    sleep = 282,

    app1 = 283,
    app2 = 284,

    audiorewind = 285,
    audiofastforward = 286,

    softleft = 287,
    softright = 288,
    call = 289,
    endcall = 290,
};
