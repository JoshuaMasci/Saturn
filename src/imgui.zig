pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
});

const glfw = @import("glfw_platform.zig");

pub const Layer = struct {
    const Self = @This();

    context: *c.ImGuiContext,

    pub fn init() Self {
        var context = c.igCreateContext(undefined);
        var io = c.igGetIO().*;
        io.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;

        return Self{
            .context = context,
        };
    }

    pub fn deinit(self: Self) void {
        c.igDestroyContext(self.context);
    }

    pub fn update(self: Self, window: glfw.WindowId) void {
        var io = c.igGetIO().*;

        //Window size update
        var size = glfw.getWindowSize(window);
        io.DisplaySize = c.ImVec2{
            .x = @intToFloat(f32, size[0]),
            .y = @intToFloat(f32, size[1]),
        };

        if (glfw.input.getMousePos()) |mouse_pos| {
            io.MousePos = c.ImVec2{
                .x = mouse_pos[0],
                .y = mouse_pos[1],
            };
        }
    }
};
