const std = @import("std");
const glfw = @import("glfw_platform.zig");
const vulkan = @import("vulkan.zig");

pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
});

pub const Layer = struct {
    const Self = @This();

    context: *c.ImGuiContext,
    io: *c.ImGuiIO,

    pub fn init() Self {
        var context = c.igCreateContext(undefined);
        var io = c.igGetIO();
        io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
        io.*.DeltaTime = 1.0 / 60.0;

        var pixels: ?[*]u8 = undefined;
        var width: i32 = undefined;
        var height: i32 = undefined;
        var bytes: i32 = 0;

        c.ImFontAtlas_GetTexDataAsRGBA32(io.*.Fonts, @ptrCast([*c][*c]u8, &pixels), &width, &height, &bytes);

        return Self{
            .context = context,
            .io = io,
        };
    }

    pub fn deinit(self: Self) void {
        c.igDestroyContext(self.context);
    }

    pub fn update(self: Self, window: glfw.WindowId) void {

        //Window size update
        var size = glfw.getWindowSize(window);
        self.io.DisplaySize = c.ImVec2{
            .x = @intToFloat(f32, size[0]),
            .y = @intToFloat(f32, size[1]),
        };

        if (glfw.input.getMousePos()) |mouse_pos| {
            self.io.MousePos = c.ImVec2{
                .x = mouse_pos[0],
                .y = mouse_pos[1],
            };
        }

        std.log.info("Here1", .{});
        c.igNewFrame();
        std.log.info("Here2.1", .{});
    }

    pub fn draw(self: Self, command_buffer: vulkan.vk.CommandBuffer) void {
        std.log.info("Here2.2", .{});
        c.igEndFrame();
        std.log.info("Here3", .{});
        c.igRender();
    }
};
