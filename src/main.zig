pub const std = @import("std");
const panic = std.debug.panic;

pub const GeneralPurposeAllocator: type = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true });

const glfw = @import("glfw");
const vk = @import("vulkan");

const Input = @import("input.zig").Input;

const Instance = @import("vulkan/instance.zig");
const Device = @import("vulkan/device.zig");
const RenderDevice = @import("render_device.zig").RenderDevice;
const Renderer = @import("renderer.zig").Renderer;

const render_graph = @import("renderer/render_graph.zig");
const pipeline = @import("renderer/pipeline.zig");

pub fn main() !void {
    var global_allocator: GeneralPurposeAllocator = GeneralPurposeAllocator{};
    defer {
        const leaked = global_allocator.deinit();
        if (leaked) panic("Error: memory leaked", .{});
    }

    var allocator = global_allocator.allocator();

    try glfw.init(.{});
    defer glfw.terminate();

    const window = try glfw.Window.create(1600, 900, "Saturn V0.0", null, null, .{
        .client_api = .no_api,
    });
    defer window.destroy();
    try window.maximize();

    var input = try Input.init(window, allocator);
    defer input.deinit();

    var instance = try Instance.init(allocator, "Saturn RenderGraph Test", Instance.AppVersion(0, 0, 1, 0));
    defer instance.deinit();

    var surface = try instance.createSurface(window);
    defer instance.destroySurface(surface);

    //TODO: select_device correctly
    var selected_device = instance.pdevices[0];
    var selected_queue_index: u32 = 0;

    //TODO: worry about pointer referencing if moved out of main!
    var device = try Device.init(allocator, instance.dispatch, selected_device, selected_queue_index);
    defer device.deinit();

    var render_device = try RenderDevice.init(allocator, &device);
    defer render_device.deinit();

    var renderer = try Renderer.init(allocator, &render_device, surface);
    defer renderer.deinit();

    //TEST_CODE_START
    var permanent_buffer = try render_device.createBuffer(.{
        .size = 16,
        .usage = .{ .storage_buffer_bit = true },
        .memory_usage = .cpu_to_gpu,
    });
    defer render_device.destroyBuffer(permanent_buffer);
    var some_data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8 };
    try render_device.fillBuffer(permanent_buffer, u8, &some_data);

    var permanent_image = try render_device.createImage(.{
        .size = .{ 16, 16 },
        .format = .r8g8b8a8_unorm,
        .usage = .{ .storage_bit = true },
        .memory_usage = .gpu_only,
    });
    defer render_device.destroyImage(permanent_image);
    //TEST_CODE_END

    var prev_time: f64 = 0.0;
    while (!window.shouldClose()) {
        var current_time = glfw.getTime();

        input.update();
        try glfw.pollEvents();

        //TEST_CODE_START
        var render_graph_builder = render_graph.RenderGraphBuilder.init(allocator);
        defer render_graph_builder.deinit();

        var some_buffer = render_graph_builder.createBuffer(.{
            .size = 16,
            .usage = .{ .storage_buffer_bit = true },
            .location = .gpu_only,
        });
        var some_image = render_graph_builder.createImage(.{
            .size = .{ 16, 16 },
            .format = .r8g8b8a8_unorm,
            .usage = .{ .storage_bit = true },
            .location = .gpu_only,
        });

        var test_pass = render_graph_builder.createRenderPass("TestRenderPass");
        render_graph_builder.addBufferAccess(test_pass, some_buffer, .shader_read);
        render_graph_builder.addRaster(test_pass, &[_]render_graph.ImageResourceHandle{some_image}, null);
        render_graph_builder.addRenderFunction(test_pass, null, testRenderFunction);
        //TEST_CODE_END

        try renderer.render();

        prev_time = current_time;
    }
}

const TestData = struct {
    some: i32,
};

fn testRenderFunction(data: *render_graph.RenderPassData) void {
    if (data.get(TestData)) |test_data| {
        std.log.info("testRenderFunction data: {}", .{test_data.some});
    } else {
        std.log.info("testRenderFunction data: null", .{});
    }
}
