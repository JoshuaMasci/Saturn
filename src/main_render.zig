// Main File for Rendering Sandbox

const std = @import("std");

const zm = @import("zmath");

const AssetRegistry = @import("asset/registry.zig");
const Scene = @import("asset/scene.zig");
const Imgui = @import("imgui.zig");
const sdl3 = @import("platform/sdl3.zig");
const Camera = @import("rendering/camera.zig").Camera;
const ImguiRenderer = @import("rendering/imgui_renderer.zig");
const RenderScene = @import("rendering/scene.zig").RenderScene;
const SceneRenderer = @import("rendering/scene_renderer.zig");
const Device = @import("rendering/vulkan/device.zig");
const Transform = @import("transform.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true }){};
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("DebugAllocator has a memory leak!", .{});
    };
    const allocator = debug_allocator.allocator();

    var app: App = try .init(allocator);
    defer app.deinit();

    const scene_filepath = "zig-out/game-assets/Bistro/scene.json";
    {
        var scene_json: std.json.Parsed(Scene) = undefined;
        {
            var file = try std.fs.cwd().openFile(scene_filepath, .{ .mode = .read_only });
            defer file.close();
            scene_json = try Scene.deserialzie(allocator, file.reader());
        }
        defer scene_json.deinit();

        const render_scene = try scene_json.value.createRenderScene(allocator, .{});

        var camera: Camera = .Default;
        var camera_transform: Transform = .{};

        if (scene_json.value.getNodeFromName("Camera")) |camera_node| {
            if (scene_json.value.nodes[camera_node].camera) |node_camera| {
                camera = node_camera;
            }

            camera_transform = scene_json.value.calcNodeGlobalTransform(camera_node);
            camera_transform.rotation = zm.qmul(zm.quatFromRollPitchYaw(0.0, std.math.pi, 0.0), camera_transform.rotation);
        }

        app.scene_info = .{
            .scene = render_scene,
            .camera = camera,
            .camera_transform = camera_transform,
        };
    }

    var last_frame_time_ns = std.time.nanoTimestamp();

    while (app.is_running()) {
        const current_time_ns = std.time.nanoTimestamp();
        const delta_time_ns = current_time_ns - last_frame_time_ns;
        const delta_time_s = @as(f32, @floatFromInt(delta_time_ns)) / std.time.ns_per_s;
        last_frame_time_ns = current_time_ns;

        try app.update(delta_time_s, debug_allocator.total_requested_bytes);
    }
}

const App = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    platform_input: sdl3.Input,
    window: sdl3.Window,
    imgui: Imgui,
    asset_registry: *AssetRegistry,

    vulkan_device: *Device,
    scene_renderer: SceneRenderer,
    imgui_renderer: ImguiRenderer,

    scene_info: ?struct {
        scene: RenderScene,
        camera: Camera,
        camera_transform: Transform,
    } = null,

    temp_allocator: std.heap.ArenaAllocator,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const asset_registry = try allocator.create(AssetRegistry);
        errdefer allocator.destroy(asset_registry);

        asset_registry.* = .init(allocator);
        try asset_registry.addRepository("engine", "zig-out/assets");
        try asset_registry.addRepository("game", "zig-out/game-assets");
        errdefer asset_registry.deinit();

        try sdl3.init(allocator);

        const imgui: Imgui = try .init(allocator);
        errdefer imgui.deinit();

        var platform_input: sdl3.Input = try .init(allocator);
        errdefer platform_input.deinit();

        var window: sdl3.Window = .init("Saturn Render Sandbox", .{ .windowed = .{ 1920, 1080 } });
        errdefer window.deinit();

        const vulkan_device = try allocator.create(Device);
        errdefer allocator.destroy(vulkan_device);

        const FRAME_IN_FLIGHT_COUNT = 3;
        const swapchain_format = .b8g8r8a8_unorm;
        const depth_format = .d16_unorm;

        vulkan_device.* = try .init(allocator, FRAME_IN_FLIGHT_COUNT);
        errdefer vulkan_device.deinit();

        try vulkan_device.claimWindow(
            window,
            .{
                .image_count = FRAME_IN_FLIGHT_COUNT,
                .format = swapchain_format,
                .present_mode = .immediate_khr,
            },
        );

        var scene_renderer: SceneRenderer = try .init(
            allocator,
            asset_registry,
            vulkan_device,
            swapchain_format,
            depth_format,
            vulkan_device.bindless_layout,
        );
        errdefer scene_renderer.deinit();

        var imgui_renderer: ImguiRenderer = try .init(
            allocator,
            asset_registry,
            vulkan_device,
            imgui.context,
            swapchain_format,
            vulkan_device.bindless_layout,
        );
        errdefer imgui_renderer.deinit();

        return .{
            .allocator = allocator,
            .asset_registry = asset_registry,
            .platform_input = platform_input,
            .window = window,
            .imgui = imgui,
            .vulkan_device = vulkan_device,
            .scene_renderer = scene_renderer,
            .imgui_renderer = imgui_renderer,
            .temp_allocator = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.scene_info) |*info| {
            info.scene.deinit();
        }

        self.temp_allocator.deinit();

        self.vulkan_device.waitIdle();

        self.scene_renderer.deinit();
        self.imgui_renderer.deinit();
        self.vulkan_device.releaseWindow(self.window);
        self.vulkan_device.deinit();
        self.allocator.destroy(self.vulkan_device);

        self.imgui.deinit();
        self.window.deinit();
        self.platform_input.deinit();

        sdl3.deinit();

        self.asset_registry.deinit();
        self.allocator.destroy(self.asset_registry);
    }

    pub fn is_running(self: Self) bool {
        return !self.platform_input.should_quit;
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?usize) !void {
        _ = self.temp_allocator.reset(.retain_capacity);
        const temp_allocator = self.temp_allocator.allocator();

        {
            self.timer += delta_time;
            self.frames += 1;
            if (self.timer > 0.1) {
                const avr_delta_time = self.timer / self.frames;
                self.average_dt = avr_delta_time;
                self.timer = 0.0;
                self.frames = 0;
            }
        }

        try self.platform_input.proccessEvents(.{});
        self.imgui.updateInput(&self.platform_input);

        {
            const window_size = self.window.getSize();
            self.imgui.startFrame(window_size, delta_time);
            defer self.imgui.context.endFrame();

            if (self.imgui.context.begin("Performance", null, .{})) {
                self.imgui.context.textFmt("Delta Time: {d:.3} ms", .{self.average_dt * 1000});
                self.imgui.context.textFmt("FPS: {d:.3}", .{1.0 / self.average_dt});
                if (mem_usage_opt) |mem_usage| {
                    const formatted_string: ?[]const u8 = @import("utils.zig").format_bytes(temp_allocator, mem_usage) catch null;
                    if (formatted_string) |mem_usage_string| {
                        defer temp_allocator.free(mem_usage_string);
                        self.imgui.context.textFmt("Memory Usage: {s}", .{mem_usage_string});
                    }
                }
            }
            self.imgui.context.end();
        }

        var render_graph = Device.RenderGraph.init(temp_allocator);
        defer render_graph.deinit();

        {
            const swapchain_texture = try render_graph.acquireSwapchainTexture(self.window);

            if (self.scene_info) |info| {
                const depth_texture = try render_graph.createTransientTexture(.{
                    .extent = .{ .relative = swapchain_texture },
                    .format = .d16_unorm,
                    .usage = .{ .depth_stencil_attachment_bit = true },
                });

                try self.scene_renderer.createRenderPass(
                    temp_allocator,
                    swapchain_texture,
                    depth_texture,
                    &info.scene,
                    info.camera,
                    info.camera_transform,
                    &render_graph,
                );
            } else {
                var render_pass = try Device.RenderPass.init(temp_allocator, "Screen Pass");
                try render_pass.addColorAttachment(.{
                    .texture = swapchain_texture,
                    .clear = .{ .float_32 = @splat(0.25) },
                    .store = true,
                });
                try render_graph.render_passes.append(render_pass);
            }

            try self.imgui_renderer.createRenderPass(temp_allocator, swapchain_texture, &render_graph);
        }

        try self.vulkan_device.render(temp_allocator, render_graph);
    }
};
