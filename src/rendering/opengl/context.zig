const std = @import("std");
const sdl = @import("zsdl2");
const opengl = @import("zopengl");
const gl = opengl.bindings;

const Settings = @import("../../rendering/settings.zig");

pub const Sdl2Context = struct {
    const Self = @This();

    window: *sdl.Window,
    gl_context: ?sdl.gl.Context,

    pub fn init_window(name: [:0]const u8, size: Settings.WindowSize, vsync: Settings.VerticalSync) !Self {
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
            sdl.Window.pos_undefined,
            sdl.Window.pos_undefined,
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
            .off => 0,
        });

        return .{
            .window = window,
            .gl_context = gl_context,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.gl_context) |gl_context| {
            sdl.gl.deleteContext(gl_context);
        }
        sdl.Window.destroy(self.window);
    }

    pub fn getWindowSize(self: Self) ![2]u32 {
        var width: i32 = 0;
        var height: i32 = 0;
        try sdl.Window.getSize(self.window, &width, &height);
        return .{ @intCast(width), @intCast(height) };
    }

    pub fn swapWindow(self: Self) void {
        sdl.gl.swapWindow(self.window);
    }
};
