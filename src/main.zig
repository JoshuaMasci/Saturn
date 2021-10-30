usingnamespace @import("core.zig");
const panic = std.debug.panic;

pub const GeneralPurposeAllocator: type = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true });

const glfw = @import("glfw/platform.zig");
const renderer = @import("renderer.zig");

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

    var vulkan_renderer = try renderer.Renderer.init(&global_allocator.allocator, glfw.getWindowHandle(window));
    defer vulkan_renderer.deinit();

    while (glfw.shouldCloseWindow(window)) {
        glfw.update();
        try vulkan_renderer.render();
    }
}
