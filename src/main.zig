const std = @import("std");

const glfw = @import("glfw_platform.zig");
usingnamespace @import("vulkan.zig");

const panic = std.debug.panic;
const GeneralPurposeAllocator: type = std.heap.GeneralPurposeAllocator(.{});

pub fn main() !void {
    var globalAllocator: GeneralPurposeAllocator = GeneralPurposeAllocator{};
    defer {
        const leaked = globalAllocator.deinit();
        if (leaked) panic("Error: memory leaked", .{});
    }

    glfw.init();
    defer glfw.deinit();

    var window = try glfw.createWindow(1600, 900, "Saturn V0.0");
    defer glfw.destoryWindow(window);
    //glfw.setMouseCaptured(window, true);
    glfw.maximizeWindow(window);

    var instance = try Instance.init(&globalAllocator.allocator, "Saturn Editor", makeVkVersion(0, 0, 0), window);
    defer instance.deinit();

    var device = try instance.createDevice(0);
    defer device.deinit();

    var tri_buffer = try Buffer.init(
        &device,
        @sizeOf(@TypeOf(vertices)),
        .{ .vertex_buffer_bit = true },
        .{ .host_visible_bit = true },
    );
    defer tri_buffer.deinit();
    try tri_buffer.fill(Vertex, &vertices);

    while (glfw.shouldCloseWindow(window)) {
        glfw.update();

        var result = try device.beginFrame();
        if (result) |command_buffer| {
            const offset = [_]vk.DeviceSize{0};
            vkd.cmdBindVertexBuffers(command_buffer, 0, 1, @ptrCast([*]const vk.Buffer, &tri_buffer.handle), &offset);
            vkd.cmdDraw(command_buffer, vertices.len, 1, 0, 0);

            try device.endFrame();
        }
    }

    device.waitIdle();
}

const Vertex = struct {
    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @byteOffsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @byteOffsetOf(Vertex, "color"),
        },
    };

    pos: [2]f32,
    color: [3]f32,
};

pub const vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.75 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.75, 0.75 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.75, 0.75 }, .color = .{ 0, 0, 1 } },
};
