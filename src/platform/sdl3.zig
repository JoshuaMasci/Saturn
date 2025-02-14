const std = @import("std");

const input = @import("../input.zig");
const App = @import("../app.zig").App;

pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    // For programs that provide their own entry points instead of relying on SDL's main function
    // macro magic, 'SDL_MAIN_HANDLED' should be defined before including 'SDL_main.h'.
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

pub const Platform = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    should_quit: bool,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const version = c.SDL_GetVersion();
        std.log.info("Starting sdl {}.{}.{}", .{ c.SDL_VERSIONNUM_MAJOR(version), c.SDL_VERSIONNUM_MINOR(version), c.SDL_VERSIONNUM_MICRO(version) });

        const failed = c.SDL_Init(c.SDL_INIT_EVENTS | c.SDL_INIT_GAMEPAD | c.SDL_INIT_HAPTIC);
        if (!failed) {
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
    }
};
