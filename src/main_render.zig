// Main File for Rendering Sandbox

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
const UnifiedGeometryBuffer = @import("rendering/unified_geometry_buffer.zig");

const DEPTH_FORMAT: vk.Format = .d32_sfloat;

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true }){};
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("DebugAllocator has a memory leak!", .{});
    };
    const allocator = debug_allocator.allocator();

    var app: App = try .init(allocator);
    defer app.deinit();

    {
        var scene: RenderScene = .init(allocator);
        errdefer scene.deinit(app.vulkan_backend);

        var camera: DebugCamera = .{};

        var scene_filepath_opt: ?[]const u8 = undefined;
        scene_filepath_opt = null;
        //scene_filepath_opt = "zig-out/game-assets/Sponza/NewSponza_Main_glTF_002/scene.json";
        scene_filepath_opt = "zig-out/game-assets/Bistro/scene.json";

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

            try scene_json.value.loadScene(&scene, .{});

            if (scene_json.value.getNodeFromName("Camera")) |camera_node| {
                if (scene_json.value.nodes[camera_node].camera) |node_camera| {
                    camera.camera = node_camera;
                }

                camera.transform = scene_json.value.calcNodeGlobalTransform(camera_node);
                camera.transform.rotation = zm.qmul(zm.quatFromRollPitchYaw(0.0, std.math.pi, 0.0), camera.transform.rotation);
            }
        }

        //Load scene
        {
            const now = std.time.nanoTimestamp();
            defer {
                const duration_ns = std.time.nanoTimestamp() - now;
                const duration_ns_f: f32 = @floatFromInt(duration_ns);
                std.log.info("Loading scene assets took {d:0.5} secs", .{duration_ns_f / std.time.ns_per_s});
            }
            try app.loadScene(scene, camera);
        }
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
    asset_registry: *AssetRegistry,

    vulkan_backend: *Backend,

    resources: Resources,

    scene_renderer: SceneRenderer,
    imgui_renderer: ImguiRenderer,

    scene_info: ?struct {
        scene: RenderScene,
        camera: DebugCamera,
    } = null,

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
        const asset_registry = try allocator.create(AssetRegistry);
        errdefer allocator.destroy(asset_registry);

        asset_registry.* = .init(allocator);
        try asset_registry.addRepository("engine", "zig-out/assets");
        try asset_registry.addRepository("game", "zig-out/game-assets");
        errdefer asset_registry.deinit();

        try sdl3.init(allocator);

        var platform_input: sdl3.Input = try .init(allocator);
        errdefer platform_input.deinit();

        var window: sdl3.Window = .init("Saturn Render Sandbox", .{ .windowed = .{ 1920, 1080 } });
        errdefer window.deinit();

        const vulkan_backend = try allocator.create(Backend);
        errdefer allocator.destroy(vulkan_backend);

        const FRAME_IN_FLIGHT_COUNT = 3;
        const swapchain_format = .b8g8r8a8_unorm;

        vulkan_backend.* = try .init(allocator, FRAME_IN_FLIGHT_COUNT);
        errdefer vulkan_backend.deinit();

        //For best Perf testing, the renderer should not be limited to monitor refresh
        try vulkan_backend.claimWindow(
            window,
            .{
                .image_count = FRAME_IN_FLIGHT_COUNT,
                .format = swapchain_format,
                .vsync = false,
            },
        );
        errdefer vulkan_backend.releaseWindow(window);

        var resources: Resources = try .init(allocator, asset_registry, vulkan_backend);
        errdefer resources.deinit();

        var scene_renderer: SceneRenderer = try .init(
            allocator,
            asset_registry,
            vulkan_backend,
            swapchain_format,
            DEPTH_FORMAT,
            vulkan_backend.bindless_layout,
        );
        errdefer scene_renderer.deinit();

        _ = imgui.ImGui_CreateContext(null) orelse return error.ImGuiCreateContextFailure;
        errdefer imgui.ImGui_DestroyContext(null);
        imgui.ImGui_StyleColorsClassic(null);

        var io: *imgui.ImGuiIO = imgui.ImGui_GetIO();
        io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableKeyboard;
        io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableGamepad;
        io.ConfigFlags |= imgui.ImGuiConfigFlags_DockingEnable;
        //io.ConfigFlags |= imgui.ImGuiConfigFlags_ViewportsEnable;

        if (!imgui.cImGui_ImplSDL3_InitForVulkan(@ptrCast(window.handle))) return error.cImGui_ImplSDL3_InitForVulkanFailure;
        errdefer imgui.cImGui_ImplSDL3_Shutdown();

        var imgui_renderer: ImguiRenderer = try .init(
            allocator,
            vulkan_backend,
            swapchain_format,
        );
        errdefer imgui_renderer.deinit();

        return .{
            .allocator = allocator,
            .asset_registry = asset_registry,
            .platform_input = platform_input,
            .window = window,
            .vulkan_backend = vulkan_backend,
            .resources = resources,
            .scene_renderer = scene_renderer,
            .imgui_renderer = imgui_renderer,
            .temp_allocator = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.scene_info) |*info| {
            info.scene.deinit(self.vulkan_backend);
        }

        self.temp_allocator.deinit();

        self.vulkan_backend.waitIdle();

        self.scene_renderer.deinit();
        self.imgui_renderer.deinit();
        self.resources.deinit();
        self.vulkan_backend.releaseWindow(self.window);
        self.vulkan_backend.deinit();
        self.allocator.destroy(self.vulkan_backend);

        imgui.cImGui_ImplSDL3_Shutdown();
        imgui.ImGui_DestroyContext(null);

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

        try self.platform_input.proccessEvents(
            .{
                .on_event = on_event,
            },
            .{
                .data = @ptrCast(self),
                .resize = window_resize,
            },
        );

        //Camera Movement
        if (self.scene_info) |*info| {
            info.camera.update(&self.platform_input, delta_time);
        }

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
                _ = imgui.ImGui_Checkbox("Enable Gpu Culling", &self.scene_renderer.gpu_culling);

                if (self.vulkan_backend.device.extensions.mesh_shader)
                    _ = imgui.ImGui_Checkbox("Enable Mesh Shading", &self.scene_renderer.mesh_shading);

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

        var render_graph = Backend.RenderGraph.init(temp_allocator);
        defer render_graph.deinit();

        {
            const swapchain_texture = try render_graph.acquireSwapchainTexture(self.window);

            if (self.scene_info) |info| {
                const depth_texture = try render_graph.createTransientTexture(.{
                    .extent = .{ .relative = swapchain_texture },
                    .format = DEPTH_FORMAT,
                    .usage = .{ .depth_stencil_attachment_bit = true },
                });

                try self.scene_renderer.createRenderPass(
                    temp_allocator,
                    swapchain_texture,
                    depth_texture,
                    &self.resources,
                    &info.scene,
                    info.camera.camera,
                    info.camera.transform,
                    &render_graph,
                );
            } else {
                var render_pass = try Backend.RenderPass.init(temp_allocator, "Screen Clear Pass");
                try render_pass.addColorAttachment(.{
                    .texture = swapchain_texture,
                    .clear = .{ .float_32 = @splat(0.25) },
                    .store = true,
                });
                try render_graph.render_passes.append(render_graph.allocator, render_pass);
            }

            try self.imgui_renderer.createRenderPass(temp_allocator, swapchain_texture, &render_graph);
        }

        try self.vulkan_backend.render(temp_allocator, render_graph);
    }

    pub fn renderBlankScreen(self: *Self, temp_allocator: std.mem.Allocator, color: zm.Vec) !void {
        try self.platform_input.proccessEvents(
            .{
                .on_event = on_event,
            },
            .{
                .data = @ptrCast(self),
                .resize = window_resize,
            },
        );

        var render_graph = Backend.RenderGraph.init(temp_allocator);
        defer render_graph.deinit();
        const swapchain_texture = try render_graph.acquireSwapchainTexture(self.window);

        {
            var render_pass = try Backend.RenderPass.init(temp_allocator, "Screen Clear Pass");
            try render_pass.addColorAttachment(.{
                .texture = swapchain_texture,
                .clear = .{ .float_32 = color },
                .store = true,
            });
            try render_graph.render_passes.append(render_graph.allocator, render_pass);
        }

        try self.vulkan_backend.render(temp_allocator, render_graph);
    }

    pub fn loadScene(self: *Self, scene: RenderScene, camera: DebugCamera) !void {
        if (self.scene_info) |*old| {
            old.scene.deinit(self.vulkan_backend);
        }

        var new_scene = scene;

        _ = self.temp_allocator.reset(.retain_capacity);
        const temp_allocator = self.temp_allocator.allocator();
        try self.renderBlankScreen(temp_allocator, @splat(0.0));

        while (!self.resources.tryLoadSceneAssets(temp_allocator, &new_scene) and !self.platform_input.should_quit) {
            _ = self.temp_allocator.reset(.retain_capacity);
            try self.renderBlankScreen(temp_allocator, @splat(0.0));
        }

        try new_scene.update(self.allocator, self.vulkan_backend, &self.resources);
        self.scene_info = .{
            .scene = new_scene,
            .camera = camera,
        };

        // Don't need to keep the memory costs of loads around after this
        _ = self.temp_allocator.reset(.free_all);
    }
};

fn on_event(data: ?*anyopaque, event: *const sdl3.Event) void {
    _ = data; // autofix
    _ = imgui.cImGui_ImplSDL3_ProcessEvent(@ptrCast(event));
}

fn window_resize(data: ?*anyopaque, window: sdl3.Window, size: [2]u32) void {
    _ = size; // autofix
    const app: *App = @ptrCast(@alignCast(data.?));

    //IDK if I should do this here, it probably could cause a race condition
    if (app.vulkan_backend.swapchains.get(window)) |swapchain| {
        swapchain.swapchain.out_of_date = true;
    }
}

pub fn ImFmtText(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const fmt_str: [:0]const u8 = try std.fmt.allocPrintSentinel(allocator, fmt, args, 0);
    defer allocator.free(fmt_str);
    imgui.ImGui_Text(fmt_str);
}
