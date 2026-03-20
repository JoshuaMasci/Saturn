const std = @import("std");

//const ig = @import("cimgui_docking");

const saturn = @import("root.zig");

const Self = @This();

device: saturn.DeviceInterface,
font_texture: ?saturn.TextureHandle = null,

pub fn init(device: saturn.DeviceInterface) !Self {
    return .{ .device = device };
}

pub fn deinit(self: *Self) void {
    _ = self; // autofix
}

pub fn addRenderPasses(target: saturn.RGTextureHandle, render_graph: *saturn.RenderGraph) error{OutOfMemory}!void {
    _ = target; // autofix
    _ = render_graph; // autofix
}
