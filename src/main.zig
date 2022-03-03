pub const std = @import("std");
const panic = std.debug.panic;

pub const GeneralPurposeAllocator: type = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true });

const glfw = @import("glfw");

const Input = @import("input.zig").Input;

const vulkan = @import("vulkan/instance.zig");
const Device = @import("vulkan/device.zig").Device;
const RenderDevice = @import("render_device.zig").RenderDevice;

const render_graph = @import("renderer/render_graph.zig");
const pipeline = @import("renderer/pipeline.zig");

pub fn main() !void {
    // var identity = Matrix4.identity;
    // var scale = Matrix4.scale(Vector3.new(1, 2, 3));
    // var translation = Matrix4.translation(Vector3.new(1, 2, 3));
    // var rotation = Matrix4.rotation(Quaternion.axisAngle(Vector3.yaxis, 3.1415926 / 4.0));
    // var multiply = translation.mul(scale).mul(rotation);
    // var model = Matrix4.model(Vector3.new(1, 2, 3), Quaternion.axisAngle(Vector3.yaxis, 3.1415926 / 4.0), Vector3.new(1, 2, 3));
    // var perspective = Matrix4.perspective_lh_zo(3.1415926 / 4.0, 1, 0.1, 100);

    // std.log.info("Identity   : {d:0.2}", .{identity.data});
    // std.log.info("scale      : {d:0.2}", .{scale.data});
    // std.log.info("translation: {d:0.2}", .{translation.data});
    // std.log.info("rotation   : {d:0.2}", .{rotation.data});
    // std.log.info("multiply   : {d:0.2}", .{multiply.data});
    // std.log.info("model      : {d:0.2}", .{model.data});
    // std.log.info("perspective: {d:0.2}", .{perspective.data});

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

    var instance = try vulkan.Instance.init(allocator, "Saturn RenderGraph Test", vulkan.AppVersion(0, 0, 1, 0));
    defer instance.deinit();
    var selected_device = instance.pdevices[0];
    var selected_queue_index: u32 = 0;

    //TODO: worry about pointer referencing if moved out of main!
    var device = try Device.init(allocator, instance.dispatch, selected_device, selected_queue_index);
    defer device.deinit();

    var render_device = try RenderDevice.init(allocator, &device);
    defer render_device.deinit();

    var prev_time: f64 = 0.0;
    while (!window.shouldClose()) {
        var current_time = glfw.getTime();

        input.update();
        try glfw.pollEvents();

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
