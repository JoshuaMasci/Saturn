const std = @import("std");

const saturn = @import("../root.zig");

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_vulkan.h");
});

pub fn beginDocking() void {
    _ = c.ImGui_DockSpaceOverViewportEx(0, c.ImGui_GetMainViewport(), c.ImGuiDockNodeFlags_PassthruCentralNode, null);
}

pub fn showDemoWindow(open: ?*bool) void {
    c.ImGui_ShowDemoWindow(open);
}

pub fn begin(name: [:0]const u8, open: ?*bool, flags: c_int) bool {
    return c.ImGui_Begin(name, open, flags);
}

pub fn end() void {
    c.ImGui_End();
}

pub fn text(label: [:0]const u8) void {
    c.ImGui_Text(label);
}

pub fn labelText(label: [:0]const u8, str: [:0]const u8) void {
    c.ImGui_LabelText(label, str);
}

pub fn inputText(label: [:0]const u8, buffer: []u8) bool {
    return c.ImGui_InputText(label, buffer.ptr, buffer.len, 0);
}

pub fn button(label: [:0]const u8) bool {
    return c.ImGui_Button(label);
}

pub fn checkbox(label: [:0]const u8, value: *bool) bool {
    return c.ImGui_Checkbox(label, value);
}

pub fn radioButton(label: [:0]const u8, active: bool) bool {
    return c.ImGui_RadioButton(label, active);
}

pub fn sliderFloat(label: [:0]const u8, value: *f32, min: f32, max: f32) bool {
    return c.ImGui_SliderFloat(label, value, min, max);
}

pub fn beginMainMenuBar() bool {
    return c.ImGui_BeginMainMenuBar();
}
pub fn endMainMenuBar() void {
    c.ImGui_EndMainMenuBar();
}

pub fn beginMenuBar() bool {
    return c.ImGui_BeginMenuBar();
}
pub fn endMenuBar() void {
    c.ImGui_EndMenuBar();
}

pub fn beginMenu(label: [:0]const u8) bool {
    return c.ImGui_BeginMenu(label);
}
pub fn endMenu() void {
    c.ImGui_EndMenu();
}

pub fn menuItem(label: [:0]const u8) bool {
    return c.ImGui_MenuItem(label);
}

pub fn menuItemBool(label: [:0]const u8, value: ?*bool, enabled: bool) bool {
    return c.ImGui_MenuItemBoolPtr(label, null, value, enabled);
}

//TODO: impliment instead of using the Imgui Vulkan backend
// The Primairy benifits would be better integrate with the RenderGraph and make use of bindless textures
// Eventually it would be nice to completely detach from the Imgui backends but the platform impl is much more compilicated than the renderer
pub const Renderer = struct {
    const Self = @This();

    device: saturn.Device,

    pub fn init(device: saturn.Device) saturn.Error!Self {
        return .{
            .device = device,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
    }

    pub fn addRenderPasses(self: *Self, main_target: saturn.RGTextureHandle, graph: *saturn.RenderGraph) saturn.Error!void {
        _ = self; // autofix
        _ = main_target; // autofix
        _ = graph; // autofix
    }
};
