const std = @import("std");
const sdl = @import("zsdl2");
const imgui = @import("zimgui");
const opengl = @import("zopengl");
const gl = opengl.bindings;

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

        try sdl.init(.{ .video = true, .joystick = true, .gamecontroller = true, .haptic = true });

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
            sdl.Window.pos_centered,
            sdl.Window.pos_centered,
            window_width,
            window_height,
            .{ .maximized = window_maximized, .fullscreen = window_fullscreen, .resizable = true, .allow_highdpi = true, .opengl = true },
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
        sdl.gl.swapWindow(self.window);
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
