const std = @import("std");
const sdl = @import("zsdl2");

const c = @import("../c.zig");

pub const WindowSize = union(enum) {
    windowed: [2]i32,
    fullscreen,
    maximized,
};

//Used cause I have no idea how to use the pub zig version for glad
extern fn SDL_GL_GetProcAddress(proc: ?[*:0]const u8) ?*anyopaque;

pub const Platform = struct {
    const Self = @This();

    window: *sdl.Window,
    gl_context: ?sdl.gl.Context,

    pub fn init_window(name: [:0]const u8, size: WindowSize) !Self {
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

        try sdl.gl.setAttribute(sdl.gl.Attr.doublebuffer, 1);
        try sdl.gl.setAttribute(sdl.gl.Attr.context_major_version, 4);
        try sdl.gl.setAttribute(sdl.gl.Attr.context_minor_version, 6);
        try sdl.gl.setAttribute(sdl.gl.Attr.context_profile_mask, @intFromEnum(sdl.gl.Profile.core));

        const gl_context = try sdl.gl.createContext(window);

        _ = c.gladLoadGLLoader(&SDL_GL_GetProcAddress);

        std.log.info("Opengl Context:\n\tVender: {s}\n\tRenderer: {s}\n\tVersion: {s}\n\tGLSL: {s}", .{
            c.glGetString(c.GL_VENDOR),
            c.glGetString(c.GL_RENDERER),
            c.glGetString(c.GL_VERSION),
            c.glGetString(c.GL_SHADING_LANGUAGE_VERSION),
        });

        try sdl.gl.setSwapInterval(1);

        return .{ .window = window, .gl_context = gl_context };
    }

    pub fn deinit(self: *Self) void {
        if (self.gl_context) |gl_context| {
            sdl.gl.deleteContext(gl_context);
        }
        sdl.Window.destroy(self.window);
        sdl.quit();
    }

    pub fn get_window_size(self: Self) ![2]i32 {
        var width: i32 = 0;
        var height: i32 = 0;
        try sdl.Window.getSize(self.window, &width, &height);
        return .{ width, height };
    }

    pub fn gl_swap_window(self: Self) void {
        sdl.gl.swapWindow(self.window);
    }
};
