const std = @import("std");

const glfw = @import("glfw_platform.zig");

pub fn main() !void {
    std.log.info("Hello App", .{});

    glfw.init();
    defer glfw.deinit();

    var window = glfw.createWindow(1600, 900, "Nebula V0.0");
    defer glfw.destoryWindow(window);
    //glfw.setMouseCaptured(window, true);
    glfw.maximizeWindow(window);

    // var vk_instance: VkInstance = null;
    // const appInfo = VkApplicationInfo{
    //     .sType = enum_VkStructureType.VK_STRUCTURE_TYPE_APPLICATION_INFO,
    //     .pApplicationName = "Nebula_Game",
    //     .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
    //     .pEngineName = "Nebula",
    //     .engineVersion = VK_MAKE_VERSION(1, 0, 0),
    //     .apiVersion = VK_API_VERSION_1_2,
    //     .pNext = null,
    // };

    while (glfw.shouldCloseWindow(window)) {
        glfw.update();
    }
}
