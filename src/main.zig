const std = @import("std");

const glfw = @import("glfw_platform.zig");
const vk = @import("vulkan.zig");

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

    var graphics = try vk.Graphics.init(&globalAllocator.allocator, "Saturn Editor", vk.makeVkVersion(0, 0, 0), window);
    defer graphics.deinit();

    while (glfw.shouldCloseWindow(window)) {
        glfw.update();
        graphics.draw();
    }
}
