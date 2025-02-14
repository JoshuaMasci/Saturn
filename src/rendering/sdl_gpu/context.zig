const std = @import("std");
const Settings = @import("../../rendering/settings.zig");

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
});

pub const Context = struct {
    const Self = @This();

    window: *c.SDL_Window,

    pub fn init_window(name: [:0]const u8, size: Settings.WindowSize, vsync: Settings.VerticalSync) !Self {
        _ = vsync; // autofix

        var window_width: i32 = 0;
        var window_height: i32 = 0;
        var window_flags = c.SDL_WINDOW_RESIZABLE;

        switch (size) {
            .windowed => |window_size| {
                window_width = window_size[0];
                window_height = window_size[1];
            },
            .maximized => window_flags |= c.SDL_WINDOW_MAXIMIZED,
            .fullscreen => window_flags |= c.SDL_WINDOW_FULLSCREEN,
        }

        const window = c.SDL_CreateWindow(name, window_width, window_height, window_flags);

        return .{
            .window = window.?,
        };
    }

    pub fn deinit(self: *Self) void {
        c.SDL_DestroyWindow(self.window);
    }

    pub fn getWindowSize(self: Self) ![2]u32 {
        var width: i32 = 0;
        var height: i32 = 0;
        _ = c.SDL_GetWindowSize(self.window, &width, &height);
        return .{ @intCast(width), @intCast(height) };
    }

    pub fn swapWindow(self: Self) void {
        _ = self; // autofix
    }
};
