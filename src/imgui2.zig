const std = @import("std");

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_vulkan.h");
});
