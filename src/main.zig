const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const AssetRegistry = @import("asset/registry.zig");
const Scene = @import("asset/scene.zig");
const DebugCamera = @import("debug_camera.zig");
const imgui = @import("imgui.zig").c;
const sdl3 = @import("platform/sdl3.zig");
const Camera = @import("rendering/camera.zig").Camera;
const ImguiRenderer = @import("rendering/imgui_renderer.zig");
const Resources = @import("rendering/resources.zig");
const RenderScene = @import("rendering/scene.zig");
const SceneRenderer = @import("rendering/scene_renderer.zig");
const Backend = @import("rendering/vulkan/backend.zig");
const Transform = @import("transform.zig");

const DEPTH_FORMAT: vk.Format = .d32_sfloat;

const saturn = @import("root.zig");
const AssetPool = @import("rendering2/asset_pool.zig");

fn emptyGraphicsCallback(ctx: ?*anyopaque, cmd: saturn.GraphicsCommandEncoder) void {
    _ = ctx; // autofix
    _ = cmd; // autofix
}

fn emptyComputeCallback(ctx: ?*anyopaque, cmd: saturn.ComputeCommandEncoder) void {
    _ = ctx; // autofix
    _ = cmd; // autofix
}

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true }).init;
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("DebugAllocator has a memory leak!", .{});
    };
    const allocator = debug_allocator.allocator();

    var app: App = try .init(allocator);
    defer app.deinit();

    if (false) {
        const sphere_mesh_handle: AssetRegistry.Handle = .fromRepoPath("engine", "shapes/sphere.asset");
        const cube_mesh_handle: AssetRegistry.Handle = .fromRepoPath("engine", "shapes/cube.asset");
        const material_handle: AssetRegistry.Handle = .fromRepoPath("engine", "materials/transparent.asset");

        if (app.resources.tryLoadMesh(allocator, sphere_mesh_handle) and app.resources.tryLoadMesh(allocator, cube_mesh_handle) and app.resources.tryLoadMaterial(allocator, material_handle)) {
            try app.resources.updateBuffers(allocator);
            _ = try app.scene.addInstance(
                &app.resources,
                .{
                    .transform = .{ .position = .{ -4.0, 3.0, 0.0, 0.0 } },
                    .mesh = sphere_mesh_handle,
                    .materials = &.{material_handle},
                },
            );

            _ = try app.scene.addInstance(
                &app.resources,
                .{
                    .transform = .{ .position = .{ -4.0, 3.0, 2.0, 0.0 } },
                    .mesh = cube_mesh_handle,
                    .materials = &.{material_handle},
                },
            );
        }
    }

    {
        var camera: DebugCamera = .{};

        var scene_filepath_opt: ?[]const u8 = undefined;
        scene_filepath_opt = null;

        //TODO: select scene from args
        //scene_filepath_opt = "zig-out/assets/game/Sponza/NewSponza_Main_glTF_002/scene.json";
        scene_filepath_opt = "zig-out/assets/game/Bistro/scene.json";

        if (scene_filepath_opt) |scene_filepath| {
            var scene_json: std.json.Parsed(Scene) = undefined;
            {
                var file = try std.fs.cwd().openFile(scene_filepath, .{ .mode = .read_only });
                defer file.close();

                var read_buffer: [1024]u8 = undefined;
                var reader = file.reader(&read_buffer);
                scene_json = try Scene.deserialzie(allocator, &reader.interface);
            }
            defer scene_json.deinit();

            if (scene_json.value.getNodeFromName("Camera")) |camera_node| {
                if (scene_json.value.nodes[camera_node].camera) |node_camera| {
                    camera.camera = node_camera;
                }

                camera.transform = scene_json.value.calcNodeGlobalTransform(camera_node);
                camera.transform.rotation = zm.qmul(zm.quatFromRollPitchYaw(0.0, std.math.pi, 0.0), camera.transform.rotation);
            }

            // Loop though the scene and mark all assets to be loaded
            for (scene_json.value.nodes) |node| {
                if (node.mesh) |mesh| {
                    _ = try app.asset_pool.getMeshAsset(mesh.mesh);
                    for (mesh.materials) |material| {
                        _ = try app.asset_pool.getMaterialAsset(material);
                    }
                }
            }

            app.camera = camera;
        }
    }

    {
        const now = std.time.nanoTimestamp();
        defer {
            const duration_ns = std.time.nanoTimestamp() - now;
            const duration_ns_f: f32 = @floatFromInt(duration_ns);
            std.log.info("Loading assets took {d:0.5} secs", .{duration_ns_f / std.time.ns_per_s});
        }

        //TEMP: force load of all resources
        app.asset_pool.loadAllCpu();

        //TODO: load gpu assets

    }

    const formatted_string: ?[]const u8 = @import("utils.zig").formatBytes(allocator, debug_allocator.total_requested_bytes) catch null;
    if (formatted_string) |mem_usage_string| {
        std.log.info("Total Memory Usage: {s}", .{mem_usage_string});
        allocator.free(mem_usage_string);
    }

    var last_frame_time_ns = std.time.nanoTimestamp();
    while (app.isRunning()) {
        const current_time_ns = std.time.nanoTimestamp();
        const delta_time_ns = current_time_ns - last_frame_time_ns;
        const delta_time_s = @as(f32, @floatFromInt(delta_time_ns)) / std.time.ns_per_s;
        last_frame_time_ns = current_time_ns;

        try app.update(delta_time_s, debug_allocator.total_requested_bytes);
    }
}

const App = struct {
    const Self = @This();

    is_running: bool = true,

    allocator: std.mem.Allocator,

    platform: saturn.PlatformInterface,
    window: saturn.WindowHandle,
    gpu_device: saturn.DeviceInterface,

    asset_registry: *AssetRegistry,
    asset_pool: AssetPool,

    camera: DebugCamera = .{},

    temp_allocator: std.heap.ArenaAllocator,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    window_visable_flags: struct {
        debug: bool = true,
        performance: bool = true,
        viewport: bool = true,
        scene: bool = true,
        properties: bool = true,
    } = .{},

    pub fn init(allocator: std.mem.Allocator) !Self {
        const platform = try saturn.init(allocator, .{
            .app_info = .{ .name = "Saturn Engine", .version = .init(0, 0, 1, 0) },
            .validation = true,
        });
        errdefer saturn.deinit();

        const window = try platform.createWindow(.{
            .name = "Test Window",
            .resizeable = true,
            .size = .{ .windowed = .{ 1920, 1080 } },
        });
        errdefer platform.destroyWindow(window);

        const gpu_device = try platform.createDeviceBasic(window, .prefer_high_power);
        errdefer platform.destroyDevice(gpu_device);

        try gpu_device.claimWindow(
            window,
            .{
                .texture_count = 3,
                .texture_usage = .{ .attachment = true, .transfer = true },
                .texture_format = .rgba8_unorm,
                .present_mode = .fifo,
            },
        );
        errdefer gpu_device.releaseWindow(window);

        const asset_registry = try allocator.create(AssetRegistry);
        errdefer allocator.destroy(asset_registry);

        asset_registry.* = .init(allocator);
        try asset_registry.addRepository("engine", "zig-out/assets/engine");
        try asset_registry.addRepository("game", "zig-out/assets/game");
        errdefer asset_registry.deinit();

        var asset_pool: AssetPool = .init(allocator, asset_registry, gpu_device);
        errdefer asset_pool.deinit();

        return .{
            .allocator = allocator,
            .platform = platform,
            .window = window,
            .gpu_device = gpu_device,

            .asset_registry = asset_registry,
            .asset_pool = asset_pool,

            .temp_allocator = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.gpu_device.waitIdle();

        self.temp_allocator.deinit();

        self.asset_pool.deinit();
        self.asset_registry.deinit();
        self.allocator.destroy(self.asset_registry);

        self.gpu_device.releaseWindow(self.window);
        self.platform.destroyDevice(self.gpu_device);
        self.platform.destroyWindow(self.window);
        saturn.deinit();
    }

    pub fn isRunning(self: Self) bool {
        return self.is_running;
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?usize) !void {
        _ = self.temp_allocator.reset(.retain_capacity);
        const temp_allocator = self.temp_allocator.allocator();

        {
            self.timer += delta_time;
            self.frames += 1;
            if (self.timer > 0.5) {
                const avr_delta_time = self.timer / self.frames;
                self.average_dt = avr_delta_time;
                self.timer = 0.0;
                self.frames = 0;
            }
        }

        self.platform.processEvents(.{
            .ctx = self,
            .quit = quitCallback,
            .window_close_requested = windowCloseCallback,
        });

        const IMGUI_ENABLED: bool = false;
        if (IMGUI_ENABLED) {
            {
                imgui.cImGui_ImplVulkan_NewFrame();
                imgui.cImGui_ImplSDL3_NewFrame();
                imgui.ImGui_NewFrame();

                _ = imgui.ImGui_DockSpaceOverViewportEx(0, imgui.ImGui_GetMainViewport(), imgui.ImGuiDockNodeFlags_PassthruCentralNode, null);
            }

            if (imgui.ImGui_BeginMainMenuBar()) {
                if (imgui.ImGui_BeginMenu("File")) {
                    imgui.ImGui_EndMenu();
                }

                if (imgui.ImGui_BeginMenu("Windows")) {
                    _ = imgui.ImGui_MenuItemBoolPtr("Performance", null, &self.window_visable_flags.performance, true);
                    _ = imgui.ImGui_MenuItemBoolPtr("Debug", null, &self.window_visable_flags.debug, true);
                    _ = imgui.ImGui_MenuItemBoolPtr("Viewport", null, &self.window_visable_flags.viewport, true);
                    _ = imgui.ImGui_MenuItemBoolPtr("Scene", null, &self.window_visable_flags.scene, true);
                    _ = imgui.ImGui_MenuItemBoolPtr("Properties", null, &self.window_visable_flags.properties, true);
                    imgui.ImGui_EndMenu();
                }

                imgui.ImGui_EndMainMenuBar();
            }

            if (self.window_visable_flags.performance) {
                if (imgui.ImGui_Begin("Performance", &self.window_visable_flags.performance, 0)) {
                    try ImFmtText(temp_allocator, "Delta Time: {d:.3} ms", .{self.average_dt * 1000});
                    try ImFmtText(temp_allocator, "FPS: {d:.3}", .{1.0 / self.average_dt});

                    if (mem_usage_opt) |mem_usage| {
                        const formatted_string: ?[]const u8 = @import("utils.zig").formatBytes(temp_allocator, mem_usage) catch null;
                        if (formatted_string) |mem_usage_string| {
                            try ImFmtText(temp_allocator, "Memory Usage: {s}", .{mem_usage_string});
                        }
                    }

                    {
                        const formatted_string: ?[]const u8 = @import("utils.zig").formatBytes(
                            temp_allocator,
                            self.vulkan_backend.device.gpu_allocator.total_requested_bytes,
                        ) catch null;
                        if (formatted_string) |mem_usage_string| {
                            try ImFmtText(temp_allocator, "Gpu Memory Usage: {s}", .{mem_usage_string});
                        }
                    }

                    imgui.ImGui_End();
                }
            }

            if (self.window_visable_flags.debug) {
                if (imgui.ImGui_Begin("Debug", &self.window_visable_flags.debug, 0)) {
                    _ = imgui.ImGui_Checkbox("Indirect", &self.scene_renderer.indirect);
                    _ = imgui.ImGui_Checkbox("Enable Culling", &self.scene_renderer.culling);

                    var is_locked: bool = self.scene_renderer.locked_culling_info != null;
                    if (imgui.ImGui_Checkbox("Lock Culling Camera", &is_locked)) {
                        self.scene_renderer.locked_culling_info = if (is_locked) .{
                            .settings = self.camera.camera,
                            .transform = self.camera.transform,
                        } else null;
                    }

                    imgui.ImGui_End();
                }
            }

            if (self.window_visable_flags.viewport) {
                if (imgui.ImGui_Begin("Viewport", &self.window_visable_flags.viewport, 0)) {
                    const size = imgui.ImGui_GetWindowSize();
                    imgui.ImGui_Text("Window Size: %.1f x %.1f", size.x, size.y);
                    imgui.ImGui_Text("TODO: draw the scene here and not on the main swapchain");
                    imgui.ImGui_End();
                }
            }

            if (self.window_visable_flags.scene) {
                if (imgui.ImGui_Begin("Scene", &self.window_visable_flags.scene, 0)) {
                    imgui.ImGui_End();
                }
            }

            if (self.window_visable_flags.properties) {
                if (imgui.ImGui_Begin("Properties", &self.window_visable_flags.properties, 0)) {
                    imgui.ImGui_End();
                }
            }

            {
                imgui.ImGui_EndFrame();
                const io: *imgui.ImGuiIO = imgui.ImGui_GetIO();
                if ((io.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable) != 0) {
                    imgui.ImGui_UpdatePlatformWindows();
                    imgui.ImGui_RenderPlatformWindowsDefault();
                }
            }
        }

        var render_graph: saturn.RenderGraph = .init(temp_allocator);
        defer render_graph.deinit();

        {
            const swapchain_texture = try render_graph.acquireWindowTexture(self.window);

            _ = try render_graph.addGraphicsPass(
                "Pass6",
                .{ .color_attachments = &.{.{ .texture = swapchain_texture, .clear = .{ 0.25, 0.0, 0.4, 1.0 } }} },
                null,
                emptyGraphicsCallback,
            );
        }

        try self.gpu_device.submit(temp_allocator, &render_graph);
    }
};

fn quitCallback(ctx: ?*anyopaque) void {
    const app: *App = @ptrCast(@alignCast(ctx.?));
    std.log.info("App quit requested", .{});
    app.is_running = false;
}

fn windowCloseCallback(ctx: ?*anyopaque, window: saturn.WindowHandle) void {
    _ = window; // autofix

    const app: *App = @ptrCast(@alignCast(ctx.?));
    std.log.info("Window close requested", .{});
    app.is_running = false;
}

pub fn ImFmtText(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const fmt_str: [:0]const u8 = try std.fmt.allocPrintSentinel(allocator, fmt, args, 0);
    defer allocator.free(fmt_str);
    imgui.ImGui_Text(fmt_str);
}
