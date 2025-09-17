const std = @import("std");

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_vulkan.h");
});

pub const WindowInterface = struct {
    pub const Info = struct {
        name: [:0]const u8,
        p_open: *bool,
    };

    data: *anyopaque,
    get_info_fn: *const fn (data: *anyopaque) Info,
    build_fn: *const fn (data: *anyopaque) void,
};
