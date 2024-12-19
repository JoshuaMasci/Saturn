const std = @import("std");

const input = @import("../input.zig");
const App = @import("../app.zig").App;

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub const Platform = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    should_quit: bool,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const version = c.SDL_GetVersion();
        std.log.info("Starting sdl {}.{}.{}", .{ c.SDL_VERSIONNUM_MAJOR(version), c.SDL_VERSIONNUM_MINOR(version), c.SDL_VERSIONNUM_MICRO(version) });

        const ram = c.SDL_GetSystemRAM();
        const theme = c.SDL_GetSystemTheme();
        const simd = c.SDL_GetSIMDAlignment();
        const cache = c.SDL_GetCPUCacheLineSize();
        std.log.info("Ram: {} Theme: {} SIMD: {} CACHE: {}", .{ ram, theme, simd, cache });

        const failed = c.SDL_Init(c.SDL_INIT_EVENTS | c.SDL_INIT_GAMEPAD | c.SDL_INIT_HAPTIC | c.SDL_INIT_VIDEO);
        if (failed) {
            return error.SdlInitFailed;
        }

        return .{
            .allocator = allocator,
            .should_quit = false,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
        std.log.info("Quiting sdl", .{});

        c.SDL_Quit();
    }

    pub fn proccess_events(self: *Self, app: *App) !void {
        _ = app; // autofix
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                self.should_quit = true;
            }
        }
        // var event: sdl.Event = undefined;
        // while (sdl.pollEvent(&event)) {
        //     switch (event.type) {
        //         .quit => self.should_quit = true,
        //         .mousebuttondown, .mousebuttonup => if (self.mouse) |*mouse| {
        //             mouse.on_button_event(app, &event.button);
        //         },
        //         .mousemotion => if (self.mouse) |*mouse| {
        //             mouse.on_move(app, &event.motion);
        //         },
        //         .keydown, .keyup => if (self.keyboard) |*keyboard| {

        //             //TODO: move capture/free function to app
        //             if (event.key.keysym.scancode == .escape and event.key.repeat == 0 and event.key.state == .pressed) {
        //                 if (self.mouse) |*mouse| {
        //                     mouse.set_captured(!mouse.is_captured());
        //                 }
        //             }

        //             keyboard.on_button_event(app, &event.key);
        //         },
        //         else => {},
        //     }
        // }
    }
};
