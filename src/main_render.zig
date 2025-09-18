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
const MeshShading = @import("rendering/mesh_shading.zig");
const Resources = @import("rendering/resources.zig");
const RenderScene = @import("rendering/scene.zig").RenderScene;
const SceneRenderer = @import("rendering/scene_renderer.zig");
const Device = @import("rendering/vulkan/device.zig");
const Transform = @import("transform.zig");

const DEPTH_FORMAT: vk.Format = .d32_sfloat;

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true }){};
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("DebugAllocator has a memory leak!", .{});
    };
    const allocator = debug_allocator.allocator();

    var app: App = try .init(allocator);
    defer app.deinit();

    //const scene_filepath = "zig-out/game-assets/Sponza/NewSponza_Main_glTF_002/scene.json";
    const scene_filepath = "zig-out/game-assets/Bistro/scene.json";

    {
        var scene_json: std.json.Parsed(Scene) = undefined;
        {
            var file = try std.fs.cwd().openFile(scene_filepath, .{ .mode = .read_only });
            defer file.close();

            var read_buffer: [1024]u8 = undefined;
            var reader = file.reader(&read_buffer);
            scene_json = try Scene.deserialzie(allocator, &reader.interface);
        }
        defer scene_json.deinit();

        const render_scene = try scene_json.value.createRenderScene(allocator, .{});

        var camera: Camera = .Default;
        var transform: Transform = .{};

        if (scene_json.value.getNodeFromName("Camera")) |camera_node| {
            if (scene_json.value.nodes[camera_node].camera) |node_camera| {
                camera = node_camera;
            }

            transform = scene_json.value.calcNodeGlobalTransform(camera_node);
            transform.rotation = zm.qmul(zm.quatFromRollPitchYaw(0.0, std.math.pi, 0.0), transform.rotation);
        }

        const debug_camera: DebugCamera = .{
            .camera = camera,
            .transform = transform,
        };

        {
            const now = std.time.nanoTimestamp();
            app.resources.loadSceneAssets(allocator, &render_scene);
            const duration_ns = std.time.nanoTimestamp() - now;
            const duration_ns_f: f32 = @floatFromInt(duration_ns);
            std.log.info("Loading scene assets took {d:0.5} secs", .{duration_ns_f / std.time.ns_per_s});
        }

        app.scene_info = .{
            .scene = render_scene,
            .camera = debug_camera,
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
    asset_registry: *AssetRegistry,

    vulkan_device: *Device,
    resources: Resources,
    scene_renderer: SceneRenderer,
    imgui_renderer: ImguiRenderer,
    mesh_shading: MeshShading,

    scene_info: ?struct {
        scene: RenderScene,
        camera: DebugCamera,
    } = null,

    temp_allocator: std.heap.ArenaAllocator,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    window_visable_flags: struct {
        culling: bool = true,
        performance: bool = true,
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

        const vulkan_device = try allocator.create(Device);
        errdefer allocator.destroy(vulkan_device);

        const FRAME_IN_FLIGHT_COUNT = 3;
        const swapchain_format = .b8g8r8a8_unorm;

        vulkan_device.* = try .init(allocator, FRAME_IN_FLIGHT_COUNT);
        errdefer vulkan_device.deinit();

        //For best Perf testing, the renderer should not be limited to monitor refresh
        try vulkan_device.claimWindow(
            window,
            .{
                .image_count = FRAME_IN_FLIGHT_COUNT,
                .format = swapchain_format,
                .vsync = false,
            },
        );
        errdefer vulkan_device.releaseWindow(window);

        var resources: Resources = .init(allocator, asset_registry, vulkan_device);
        errdefer resources.deinit();

        var scene_renderer: SceneRenderer = try .init(
            allocator,
            asset_registry,
            vulkan_device,
            swapchain_format,
            DEPTH_FORMAT,
            vulkan_device.bindless_layout,
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
            vulkan_device,
            swapchain_format,
        );
        errdefer imgui_renderer.deinit();

        var mesh_shading: MeshShading = try .init(
            allocator,
            asset_registry,
            vulkan_device,
            swapchain_format,
            vulkan_device.bindless_layout,
        );
        errdefer mesh_shading.deinit();

        return .{
            .allocator = allocator,
            .asset_registry = asset_registry,
            .platform_input = platform_input,
            .window = window,
            .vulkan_device = vulkan_device,
            .resources = resources,
            .scene_renderer = scene_renderer,
            .imgui_renderer = imgui_renderer,
            .mesh_shading = mesh_shading,
            .temp_allocator = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.scene_info) |*info| {
            info.scene.deinit();
        }

        self.temp_allocator.deinit();

        self.vulkan_device.waitIdle();

        self.mesh_shading.deinit();
        self.scene_renderer.deinit();
        self.imgui_renderer.deinit();
        self.resources.deinit();
        self.vulkan_device.releaseWindow(self.window);
        self.vulkan_device.deinit();
        self.allocator.destroy(self.vulkan_device);

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
                _ = imgui.ImGui_MenuItemBoolPtr("Culling", null, &self.window_visable_flags.culling, true);
                imgui.ImGui_EndMenu();
            }
            imgui.ImGui_EndMainMenuBar();
        }

        if (imgui.ImGui_Begin("Viewport", null, 0)) {
            const size = imgui.ImGui_GetWindowSize();
            imgui.ImGui_Text("Window Size: %.1f x %.1f", size.x, size.y);
            imgui.ImGui_Text("TODO: draw the scene here and not on the main swapchain");
            imgui.ImGui_End();
        }

        if (self.window_visable_flags.performance and imgui.ImGui_Begin("Performance", &self.window_visable_flags.performance, 0)) {
            try ImFmtText(temp_allocator, "Delta Time: {d:.3} ms", .{self.average_dt * 1000});
            try ImFmtText(temp_allocator, "FPS: {d:.3}", .{1.0 / self.average_dt});

            if (mem_usage_opt) |mem_usage| {
                const formatted_string: ?[]const u8 = @import("utils.zig").formatBytes(temp_allocator, mem_usage) catch null;
                if (formatted_string) |mem_usage_string| {
                    try ImFmtText(temp_allocator, "Memory Usage: {s}", .{mem_usage_string});
                }
            }
            imgui.ImGui_End();
        }

        if (self.window_visable_flags.culling and imgui.ImGui_Begin("Culling", &self.window_visable_flags.culling, 0)) {
            _ = imgui.ImGui_Checkbox("Frustum Culling", &self.scene_renderer.enable_culling);
            try ImFmtText(temp_allocator, "Total Primitives: {}", .{self.scene_renderer.total_primitives});
            try ImFmtText(temp_allocator, "Rendered Primitives: {}", .{self.scene_renderer.rendered_primitives});
            try ImFmtText(temp_allocator, "Culled Primitives: {}", .{self.scene_renderer.culled_primitives});
            //imgui.ImGui_LabelText("Primitives", "%d", self.scene_renderer.total_primitives);
            imgui.ImGui_End();
        }

        if (imgui.ImGui_Begin("Entities", null, 0)) {
            imgui.ImGui_End();
        }

        {
            imgui.ImGui_EndFrame();
            const io: *imgui.ImGuiIO = imgui.ImGui_GetIO();
            if ((io.ConfigFlags & imgui.ImGuiConfigFlags_ViewportsEnable) != 0) {
                imgui.ImGui_UpdatePlatformWindows();
                imgui.ImGui_RenderPlatformWindowsDefault();
            }
        }

        var render_graph = Device.RenderGraph.init(temp_allocator);
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
                var render_pass = try Device.RenderPass.init(temp_allocator, "Screen Pass");
                try render_pass.addColorAttachment(.{
                    .texture = swapchain_texture,
                    .clear = .{ .float_32 = @splat(0.25) },
                    .store = true,
                });
                try render_graph.render_passes.append(render_graph.allocator, render_pass);
            }

            try self.mesh_shading.createRenderPass(temp_allocator, swapchain_texture, &render_graph);

            try self.imgui_renderer.createRenderPass(temp_allocator, swapchain_texture, &render_graph);
        }

        try self.vulkan_device.render(temp_allocator, render_graph);
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
    if (app.vulkan_device.swapchains.get(window)) |swapchain| {
        swapchain.swapchain.out_of_date = true;
    }
}

pub fn ImFmtText(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const fmt_str: [:0]const u8 = try std.fmt.allocPrintSentinel(allocator, fmt, args, 0);
    defer allocator.free(fmt_str);
    imgui.ImGui_Text(fmt_str);
}
