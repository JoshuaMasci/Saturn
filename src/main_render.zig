// Main File for Rendering Sandbox

const std = @import("std");

const sdl3 = @import("platform/sdl3.zig");

const Device = @import("rendering/vulkan/device.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true }){};
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("DebugAllocator has a memory leak!", .{});
    };
    const allocator = debug_allocator.allocator();

    var temp_arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer temp_arena_allocator.deinit();

    const temp_allocator = temp_arena_allocator.allocator();

    try sdl3.init(allocator);
    defer sdl3.deinit();

    var platform_input = try sdl3.Input.init(allocator);
    defer platform_input.deinit();

    var window = sdl3.Window.init("Saturn Render Sandbox", .{ .windowed = .{ 1920, 1080 } });
    defer window.deinit();

    var vulkan_device = try Device.init(allocator, 3);
    defer vulkan_device.deinit();

    try vulkan_device.claimWindow(window);
    defer vulkan_device.releaseWindow(window);

    var asset_registry = @import("asset/registry.zig").init(allocator);
    defer asset_registry.deinit();
    try asset_registry.addRepository("engine", "zig-out/assets");
    try asset_registry.addRepository("game", "zig-out/game-assets");

    while (!platform_input.should_quit) {
        _ = temp_arena_allocator.reset(.retain_capacity);
        try platform_input.proccessEvents(.{});

        var render_graph = Device.RenderGraph.init(temp_allocator);
        defer render_graph.deinit();

        {
            const swapchain_texture = try render_graph.acquireSwapchainTexture(window);
            var render_pass = try Device.RenderPass.init(temp_allocator, "Screen Pass");
            try render_pass.addColorAttachment(.{
                .texture = swapchain_texture,
                .clear = .{ .float_32 = @splat(0.25) },
                .store = true,
            });
            try render_graph.render_passes.append(render_pass);
        }

        try vulkan_device.render(temp_allocator, render_graph);
    }
}
