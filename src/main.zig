const std = @import("std");

const glfw = @import("glfw_platform.zig");

const vulkan = @import("vulkan.zig");
usingnamespace vulkan;

const imgui = @import("Imgui.zig");

const resources = @import("resources");

const panic = std.debug.panic;
const GeneralPurposeAllocator: type = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true });

pub fn main() !void {
    var global_allocator: GeneralPurposeAllocator = GeneralPurposeAllocator{};
    defer {
        const leaked = global_allocator.deinit();
        if (leaked) panic("Error: memory leaked", .{});
    }

    glfw.init();
    defer glfw.deinit();

    var window = try glfw.createWindow(1600, 900, "Saturn V0.0");
    defer glfw.destoryWindow(window);
    //glfw.setMouseCaptured(window, true);
    glfw.maximizeWindow(window);

    var instance = try Instance.init(&global_allocator.allocator, "Saturn Editor", AppVersion(0, 0, 0, 0), window);
    defer instance.deinit();

    const DeviceIndex: u32 = 0;
    const FramesInFlightCount: u32 = 3;
    try instance.createDevice(DeviceIndex, FramesInFlightCount);
    defer instance.destoryDevice(DeviceIndex);
    var device: *Device = try instance.getDevice(DeviceIndex);

    var pipeline = try device.createPipeline(
        &resources.tri_vert,
        &resources.tri_frag,
        &Vertex.binding_description,
        &Vertex.attribute_description,
        &.{},
    );
    defer device.destroyPipeline(pipeline);

    var tri_buffer_index = try device.resources.createBuffer(
        @sizeOf(@TypeOf(vertices)),
        .{ .vertex_buffer_bit = true },
        .{ .host_visible_bit = true },
    );
    defer device.resources.destoryBuffer(tri_buffer_index);
    var tri_buffer: Buffer = undefined;
    if (device.resources.getBuffer(tri_buffer_index)) |buffer| {
        tri_buffer = buffer;
    } else {
        panic("Failed to retrive buffer", .{});
    }
    try tri_buffer.fill(Vertex, &vertices);

    var imgui_layer = try imgui.Layer.init(device);
    defer imgui_layer.deinit();

    while (glfw.shouldCloseWindow(window)) {
        glfw.update();
        imgui_layer.update(window);

        var result = try device.beginFrame();
        if (result) |command_buffer| {
            vk.vkd.cmdBindPipeline(command_buffer, .graphics, pipeline);

            const offset = [_]vk.DeviceSize{0};
            vk.vkd.cmdBindVertexBuffers(command_buffer, 0, 1, @ptrCast([*]const vk.Buffer, &tri_buffer.handle), &offset);
            vk.vkd.cmdDraw(command_buffer, vertices.len, 1, 0, 0);

            imgui_layer.beginFrame();
            try imgui_layer.endFrame(command_buffer);

            try device.endFrame();
        }
    }

    device.waitIdle();
}

const Vertex = struct {
    const Self = @This();

    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Self),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @byteOffsetOf(Self, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @byteOffsetOf(Self, "color"),
        },
    };

    pos: [2]f32,
    color: [3]f32,
};

pub const vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.75 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ -0.75, 0.75 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ 0.75, 0.75 }, .color = .{ 0, 0, 1 } },
};
