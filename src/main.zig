const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const AssetRegistry = @import("asset/registry.zig");
const Scene = @import("asset/scene.zig");
const DebugCamera = @import("debug_camera.zig");
const SaturnImgui = @import("imgui.zig");
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
const TransferQueue = @import("rendering2/transfer_queue.zig");

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
        app.asset_pool.loadAllGpu();
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

    transfer_queue: TransferQueue,
    asset_pool: AssetPool,

    imgui: SaturnImgui,

    camera: DebugCamera = .{},

    temp_allocator: std.heap.ArenaAllocator,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

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

        std.log.info("GPU Device Selected: {f}", .{gpu_device.getInfo()});

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

        var asset_pool: AssetPool = try .init(allocator, asset_registry, gpu_device);
        errdefer asset_pool.deinit();

        var transfer_queue: TransferQueue = .init(allocator, gpu_device);
        errdefer transfer_queue.deinit();

        const imgui: SaturnImgui = try .init(gpu_device);

        return .{
            .allocator = allocator,
            .platform = platform,
            .window = window,
            .gpu_device = gpu_device,

            .asset_registry = asset_registry,

            .transfer_queue = transfer_queue,
            .asset_pool = asset_pool,

            .imgui = imgui,

            .temp_allocator = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.gpu_device.waitIdle();

        self.temp_allocator.deinit();

        self.imgui.deinit();

        self.asset_pool.deinit();
        self.transfer_queue.deinit();
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
        _ = mem_usage_opt; // autofix
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

        try self.asset_pool.addTransfers(&self.transfer_queue);

        var render_graph: saturn.RenderGraph = .init(temp_allocator);
        defer render_graph.deinit();

        try self.transfer_queue.buildPass(&render_graph);

        {
            const swapchain_texture = try render_graph.acquireWindowTexture(self.window);

            _ = try render_graph.addGraphicsPass(
                "Swapchain Pass",
                .{ .color_attachments = &.{.{ .texture = swapchain_texture, .clear = .{ 0.25, 0.0, 0.4, 1.0 } }} },
                null,
                emptyGraphicsCallback,
            );
        }

        try self.gpu_device.submitRenderGraph(temp_allocator, &render_graph);
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
