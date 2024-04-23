const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const zimgui = @import("zgui");

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
    window: *glfw.Window,

    pub fn init_window(allocator: std.mem.Allocator, name: [:0]const u8, size: WindowSize) !Self {
        try glfw.init();

        const gl_major = 4;
        const gl_minor = 0;
        glfw.windowHintTyped(.context_version_major, gl_major);
        glfw.windowHintTyped(.context_version_minor, gl_minor);
        glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
        glfw.windowHintTyped(.opengl_forward_compat, true);
        glfw.windowHintTyped(.client_api, .opengl_api);
        glfw.windowHintTyped(.doublebuffer, true);

        var window_width: i32 = 0;
        var window_height: i32 = 0;
        var monitor: ?*glfw.Monitor = null;
        switch (size) {
            .windowed => |window_size| {
                window_width = window_size[0];
                window_height = window_size[1];
            },
            .maximized => glfw.windowHintTyped(glfw.WindowHint.maximized, true),
            .fullscreen => monitor = glfw.Monitor.getPrimary(),
        }
        const window = try glfw.Window.create(window_width, window_height, name, monitor);

        glfw.makeContextCurrent(window);
        glfw.swapInterval(1);

        try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

        zimgui.init(allocator);
        zimgui.backend.init(window);
        zimgui.io.setConfigFlags(.{
            .dock_enable = true,
            .nav_enable_keyboard = true,
            .nav_enable_gamepad = true,
        });

        return .{
            .should_quit = false,
            .window = window,
        };
    }

    pub fn deinit(self: *Self) void {
        zimgui.backend.deinit();
        zimgui.deinit();
        self.window.destroy();
        glfw.terminate();
    }

    pub fn get_window_size(self: Self) ![2]i32 {
        return self.window.getFramebufferSize();
    }

    pub fn gl_swap_window(self: Self) void {
        zimgui.backend.draw();
        self.window.swapBuffers();
    }

    //TODO: make an abstract version of app event handler function
    pub fn proccess_events(self: *Self, app: *App) void {
        _ = app;
        glfw.pollEvents();

        if (self.window.shouldClose()) {
            self.should_quit = true;
        }

        const fb_size = self.window.getFramebufferSize();
        zimgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));
    }
};
