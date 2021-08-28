const std = @import("std");
const glfw = @import("glfw_platform.zig");
const vulkan = @import("vulkan.zig");

const resources = @import("resources");

pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
});

pub const Layer = struct {
    const Self = @This();

    context: *c.ImGuiContext,
    io: *c.ImGuiIO,

    device: *vulkan.Device,
    pipeline: vulkan.vk.Pipeline,

    pub fn init(device: *vulkan.Device) !Self {
        var context = c.igCreateContext(null);

        var io: *c.ImGuiIO = c.igGetIO();
        io.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
        io.DeltaTime = 1.0 / 60.0;

        c.igStyleColorsDark(null);

        var pixels: ?[*]u8 = undefined;
        var width: i32 = undefined;
        var height: i32 = undefined;
        var bytes: i32 = 0;
        c.ImFontAtlas_GetTexDataAsRGBA32(io.Fonts, @ptrCast([*c][*c]u8, &pixels), &width, &height, &bytes);

        var pipeline = try device.createPipeline(
            &resources.imgui_vert,
            &resources.imgui_frag,
            &ImguiVertex.binding_description,
            &ImguiVertex.attribute_description,
        );

        return Self{
            .context = context,
            .io = io,
            .device = device,
            .pipeline = pipeline,
        };
    }

    pub fn deinit(self: Self) void {
        self.device.destroyPipeline(self.pipeline);
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
        c.igNewFrame();
    }

    pub fn draw(self: Self, command_buffer: vulkan.vk.CommandBuffer) void {
        var open = true;
        c.igShowDemoWindow(&open);

        c.igEndFrame();
        c.igRender();

        vulkan.vkd.cmdBindPipeline(command_buffer, .graphics, self.pipeline);
    }
};

const ImguiVertex = struct {
    const Self = @This();

    const binding_description = vulkan.vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Self),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vulkan.vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @byteOffsetOf(Self, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32_sfloat,
            .offset = @byteOffsetOf(Self, "uv"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r8g8b8a8_unorm,
            .offset = @byteOffsetOf(Self, "color"),
        },
    };

    pos: [2]f32,
    uv: [2]f32,
    color: [4]u8,
};
