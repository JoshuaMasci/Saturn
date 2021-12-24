usingnamespace @import("core.zig");
const panic = std.debug.panic;

pub const GeneralPurposeAllocator: type = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true });

const glfw = @import("glfw");

const Input = @import("input.zig").Input;
const renderer = @import("renderer.zig");

pub fn main() !void {
    var global_allocator: GeneralPurposeAllocator = GeneralPurposeAllocator{};
    defer {
        const leaked = global_allocator.deinit();
        if (leaked) panic("Error: memory leaked", .{});
    }

    var allocator = &global_allocator.allocator;

    try glfw.init();
    defer glfw.terminate();

    try glfw.Window.hint(.client_api, glfw.no_api);
    const window = try glfw.Window.create(1600, 900, "Saturn V0.0", null, null);
    defer window.destroy();

    try window.maximize();

    var input = try Input.init(window, allocator);
    defer input.deinit();

    var vulkan_renderer = try renderer.Renderer.init(allocator, window);
    defer vulkan_renderer.deinit();

    var prev_time: f64 = 0.0;
    while (!window.shouldClose()) {
        var current_time = glfw.getTime();

        input.update();
        try glfw.pollEvents();

        vulkan_renderer.update(window, &input, @floatCast(f32, current_time - prev_time));
        try vulkan_renderer.render();
        prev_time = current_time;
    }
}
