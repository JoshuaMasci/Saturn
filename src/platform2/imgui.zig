const std = @import("std");

const saturn = @import("../root.zig");

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_vulkan.h");
});

pub fn showDemoWindow(open: ?*bool) void {
    c.ImGui_ShowDemoWindow(open);
}
