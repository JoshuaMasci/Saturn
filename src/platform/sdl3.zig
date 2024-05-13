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

pub const Platform = struct {
    const Self = @This();

    should_quit: bool,
    window: *sdl.Window,
    gl_context: ?sdl.gl.Context,

    pub fn init_window(allocator: std.mem.Allocator, name: [:0]const u8, size: WindowSize) !Self {
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

        try sdl.gl.setSwapInterval(1);

        var mouse: ?Mouse = null;
        if (sdl.hasMouse()) {
            mouse = Mouse.init();
            mouse.?.button_bindings.set(MouseButton.left, .{ .button = .debug_camera_interact });
        }

        var keyboard: ?Keyboard = null;
        if (sdl.hasKeyboard()) {
            keyboard = Keyboard.init();

            keyboard.?.button_bindings.set(Scancode.a, .{ .axis = .{ .axis = .debug_camera_left_right, .dir = .positve } });
            keyboard.?.button_bindings.set(Scancode.d, .{ .axis = .{ .axis = .debug_camera_left_right, .dir = .negitive } });

            keyboard.?.button_bindings.set(Scancode.space, .{ .axis = .{ .axis = .debug_camera_up_down, .dir = .positve } });
            keyboard.?.button_bindings.set(Scancode.lshift, .{ .axis = .{ .axis = .debug_camera_up_down, .dir = .negitive } });

            keyboard.?.button_bindings.set(Scancode.w, .{ .axis = .{ .axis = .debug_camera_forward_backward, .dir = .positve } });
            keyboard.?.button_bindings.set(Scancode.s, .{ .axis = .{ .axis = .debug_camera_forward_backward, .dir = .negitive } });
        }

        imgui.init(allocator);
        imgui.io.setConfigFlags(.{
            .dock_enable = true,
            .nav_enable_keyboard = true,
            .nav_enable_gamepad = true,
        });
        imgui.backend.init(window, gl_context);

        return .{
            .should_quit = false,
            .window = window,
            .gl_context = gl_context,
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.info("Shutting down sdl", .{});

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

    pub fn proccess_events(self: *Self, app: *App) void {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            _ = imgui.backend.processEvent(&event);

            switch (event.type) {
                .quit => self.should_quit = true,
                else => {},
            }
        }
        _ = app;
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

    fn set_captured(self: Self, captured: bool) void {
        _ = self;
        _ = sdl.SetRelativeMouseMode(captured);
    }

    fn is_captured(self: Self) bool {
        _ = self;
        return sdl.getRelativeMouseMode();
    }

    fn on_button_event(self: *Self, app: *App, event: *sdl.MouseButtonEvent) void {
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

    fn on_button_event(self: *Self, app: *App, event: *sdl.KeyboardEvent) void {
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

// Copied from zsdl, removed the "unknown" and "_" varients
// This is so they can be used with the enum array which requires a fixed number of enum varients
pub const Scancode = enum(u32) {
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
