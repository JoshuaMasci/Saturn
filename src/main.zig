usingnamespace @import("core.zig");
const panic = std.debug.panic;

pub const GeneralPurposeAllocator: type = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true });

const glfw = @import("glfw");

const Input = @import("input.zig").Input;
const renderer = @import("renderer.zig");

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
