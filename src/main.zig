const std = @import("std");
const builtin = @import("builtin");

const zm = @import("zmath");

const AssetRegistry = @import("asset/registry.zig");
const SceneAsset = @import("asset/scene.zig");
const DebugCamera = @import("debug_camera.zig");
const Camera = @import("rendering/camera.zig").Camera;
const Transform = @import("transform.zig");

const saturn = @import("root.zig");
const AssetPool = @import("rendering/asset_pool.zig");
const TransferQueue = @import("rendering/transfer_queue.zig");
const Scene = @import("rendering/scene.zig");
const SceneRenderer = @import("rendering/scene_renderer.zig");

const imgui = @import("platform/imgui.zig");

const Universe = @import("entity.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true }).init;
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("DebugAllocator has a memory leak!", .{});
    };

    const allocator = switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
        .Debug, .ReleaseSafe => debug_allocator.allocator(),
    };

    var app: App = try .init(allocator, .{
        .window_size = .maximized,
        .vsync = false,
        .power_level = .prefer_high_power,
    });
    defer app.deinit();

    try app.platform.initImgui(app.gpu_device, app.window);
    defer app.platform.deinitImgui();

    imgui.c.ImGui_StyleColorsClassic(null);

    var io: *imgui.c.ImGuiIO = imgui.c.ImGui_GetIO();
    io.ConfigFlags |= imgui.c.ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= imgui.c.ImGuiConfigFlags_NavEnableGamepad;
    io.ConfigFlags |= imgui.c.ImGuiConfigFlags_DockingEnable;
    //io.ConfigFlags |= imgui.c.ImGuiConfigFlags_ViewportsEnable; //Not functional atm

    //Adds some shapes to the scene for fun
    {
        const cube_mesh_handle: AssetPool.MeshAssetHandle = try app.asset_pool.getMeshAsset(.fromRepoPath("engine", "shapes/cube.asset"));
        const sphere_mesh_handle: AssetPool.MeshAssetHandle = try app.asset_pool.getMeshAsset(.fromRepoPath("engine", "shapes/sphere.asset"));
        const transparent_material_handle: AssetPool.MaterialAssetHandle = try app.asset_pool.getMaterialAsset(.fromRepoPath("engine", "materials/transparent.asset"));
        app.asset_pool.markAllForLoad();

        _ = try app.scene.createStaticMeshInstance(
            true,
            .{ .position = .{ -4.0, 3.0, 0.0, 0.0 } },
            sphere_mesh_handle,
            &.{transparent_material_handle},
        );

        _ = try app.scene.createStaticMeshInstance(
            true,
            .{ .position = .{ -4.0, 3.0, 2.0, 0.0 } },
            cube_mesh_handle,
            &.{transparent_material_handle},
        );

        app.camera.transform = .{ .position = .{ -4.0, 3.0, -5.0, 0.0 } };
    }

    app.scene_win.selected_world = try app.loadScene("assets/game/Sponza/NewSponza_Main_glTF_002/scene.json", true);
    //app.scene_win.selected_world = try app.loadScene("assets/game/Bistro/scene.json", true);

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
    const Config = struct {
        window_size: saturn.WindowSize,
        vsync: bool,
        power_level: saturn.DevicePowerPreference,
    };

    const Self = @This();

    is_running: bool = true,

    allocator: std.mem.Allocator,

    platform: saturn.PlatformInterface,
    window: saturn.WindowHandle,
    gpu_device: saturn.DeviceInterface,

    asset_registry: *AssetRegistry,

    transfer_queue: TransferQueue,
    asset_pool: *AssetPool,

    scene_renderer: SceneRenderer,

    universe2: Universe,
    main_world: Universe.WorldHandle,

    camera: DebugCamera = .{},
    scene: Scene,

    temp_allocator: std.heap.ArenaAllocator,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    //Editor Windows
    perf_win: PerformanceWindow = .{},
    scene_win: SceneWindow = .{},
    prop_win: PropertiesWindow = .{},
    camera_win: CameraWindow = .{},
    demo_win: DemoWindow = .{},

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        const platform = try saturn.init(allocator, .{
            .app_info = .{ .name = "Saturn Engine", .version = .init(0, 0, 1, 0) },
            .validation = true,
        });
        errdefer saturn.deinit();

        const window = try platform.createWindow(.{
            .name = "Saturn Editor",
            .resizeable = true,
            .size = config.window_size,
        });
        errdefer platform.destroyWindow(window);

        const gpu_device = try platform.createDeviceBasic(window, config.power_level);
        errdefer platform.destroyDevice(gpu_device);

        const info = gpu_device.getInfo();
        std.log.info("GPU Device Selected: {f}", .{info});

        const window_caps = platform.getWindowCapabilities(allocator, info.physical_device_index, window).?; // orelse return error.WindowNotSupported;
        defer window_caps.deinit(allocator);

        //Tries to select the prefered settings first, fallbacks to
        const vsync = config.vsync;
        const usage: saturn.TextureUsage = .{ .attachment = true, .transfer_dst = true };

        var window_settings_opt: ?saturn.WindowSettings = getPreferredWindowSettings(window_caps, usage, .@"10_bit", vsync);
        if (window_settings_opt == null) window_settings_opt = getPreferredWindowSettings(window_caps, usage, .@"8bit_unorm", true);
        const window_settings = window_settings_opt orelse return error.WindowNotSupported;

        const ColorTarget: saturn.TextureFormat = window_settings.texture_format;
        const DepthTarget: saturn.TextureFormat = .d32_float;

        const RenderTarget: SceneRenderer.RenderTargetState = .{
            .color_targets = &.{ColorTarget},
            .depth_target = DepthTarget,
        };

        try gpu_device.claimWindow(window, window_settings);
        errdefer gpu_device.releaseWindow(window);

        // Wayland won't display a window until it has been drawn to
        // So just draw a black window until everything is loaded
        // Could be an engine splash screen in the future
        {
            var render_graph: saturn.RenderGraph = .init(allocator);
            defer render_graph.deinit();
            const swapchain_texture = try render_graph.acquireWindowTexture(window);
            _ = try render_graph.addGraphicsPass(
                "Empty Swapchain Pass",
                .{ .color_attachments = &.{.{
                    .texture = swapchain_texture,
                    .clear = @splat(0.0),
                }} },
                null,
                emptyGraphicsCallback,
            );
            try gpu_device.submitRenderGraph(allocator, &render_graph);
        }

        const asset_registry = try allocator.create(AssetRegistry);
        errdefer allocator.destroy(asset_registry);

        asset_registry.* = .init(allocator);
        errdefer asset_registry.deinit();

        try asset_registry.addRepository("engine", "assets/engine");
        try asset_registry.addRepository("game", "assets/game");

        const asset_pool = try allocator.create(AssetPool);
        errdefer allocator.destroy(asset_pool);

        asset_pool.* = try .init(allocator, asset_registry, gpu_device);
        errdefer asset_pool.deinit();

        var transfer_queue: TransferQueue = .init(allocator, gpu_device);
        errdefer transfer_queue.deinit();

        var scene_renderer: SceneRenderer = try .init(allocator, gpu_device, asset_registry, RenderTarget);
        errdefer scene_renderer.deinit();

        var scene: Scene = try .init(allocator, gpu_device, asset_pool, 4096);
        errdefer scene.deinit();

        var universe2: Universe = .init(allocator);
        errdefer universe2.deinit();

        const main_world = try universe2.createWorld("Main World");
        errdefer universe2.destroyWorld(main_world, true);

        return .{
            .allocator = allocator,
            .platform = platform,
            .window = window,
            .gpu_device = gpu_device,

            .asset_registry = asset_registry,

            .transfer_queue = transfer_queue,
            .asset_pool = asset_pool,

            .scene_renderer = scene_renderer,

            .scene = scene,
            .universe2 = universe2,
            .main_world = main_world,

            .temp_allocator = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.gpu_device.waitIdle();

        self.temp_allocator.deinit();

        self.scene.deinit();
        self.universe2.deinit();

        self.scene_renderer.deinit();

        self.asset_pool.deinit();
        self.allocator.destroy(self.asset_pool);

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
        _ = self.temp_allocator.reset(.retain_capacity);
        const tpa = self.temp_allocator.allocator();

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

        self.perf_win.average_dt = self.average_dt;
        self.perf_win.mem_usage = mem_usage_opt;

        self.platform.processEvents(.{
            .ctx = self,
            .quit = quitCallback,
            .window_close_requested = windowCloseCallback,

            .gamepad_button = gamepadButtonCallback,
            .gamepad_axis = gamepadAxisCallback,
        });

        self.camera.update(delta_time);

        // LAZY WAY TO UPDATE WORLD
        // Im still deciding on the design of the entity system so im going to be lazy till then
        {
            var world_iter = self.universe2.worlds.iterator();
            while (world_iter.nextValue()) |world| {
                _ = world; // autofix
                // for (world.entities.slice()) |root_entity| {
                //     self.updateEntity(root_entity, .{});
                // }
            }
        }

        const IMGUI_ENABLED = true;
        if (IMGUI_ENABLED) {
            self.platform.beginImgui();
            imgui.beginDocking();

            //Menu
            if (imgui.beginMainMenuBar()) {
                if (imgui.beginMenu("File")) {
                    _ = imgui.menuItem("New");
                    _ = imgui.menuItem("Save");
                    _ = imgui.menuItem("Load");
                    imgui.c.ImGui_Separator();
                    if (imgui.menuItem("Load Scene")) {
                        const cwd_path = try std.fs.cwd().realpathAlloc(self.allocator, ".");
                        defer self.allocator.free(cwd_path);

                        self.platform.showFileOpenDialog(self.window, .{
                            .allow_many = false,
                            .default_location = cwd_path,
                            .filers = &.{.{ .name = "Scene Json", .pattern = "json" }},
                            .userdata = self,
                            .callback = sceneLoadCallback,
                        });
                    }

                    imgui.c.ImGui_Separator();
                    if (imgui.menuItem("Quit")) {
                        self.is_running = false;
                    }
                    imgui.endMenu();
                }

                if (imgui.beginMenu("Windows")) {
                    _ = imgui.menuItemBool(self.perf_win.name, &self.perf_win.open, true);
                    _ = imgui.menuItemBool(self.scene_win.name, &self.scene_win.open, true);
                    _ = imgui.menuItemBool(self.prop_win.name, &self.prop_win.open, true);
                    _ = imgui.menuItemBool(self.camera_win.name, &self.camera_win.open, true);
                    _ = imgui.menuItemBool(self.demo_win.name, &self.demo_win.open, true);
                    imgui.endMenu();
                }

                imgui.endMainMenuBar();
            }

            self.perf_win.draw(tpa);
            self.camera_win.draw(tpa, &self.camera, self.platform.getWindowSize(self.window));
            self.scene_win.draw(tpa, &self.universe2);
            self.prop_win.draw(tpa, &self.universe2, self.scene_win.selected);
            self.demo_win.draw();

            self.platform.endImgui();
        }

        try self.asset_pool.addTransfers(&self.transfer_queue);
        try self.scene.addTransfers(&self.transfer_queue);

        var render_graph: saturn.RenderGraph = .init(tpa);
        defer render_graph.deinit();

        try self.transfer_queue.buildPasses(&render_graph);

        const swapchain_texture = try render_graph.acquireWindowTexture(self.window);

        if (true) {
            try self.scene_renderer.addPasses(
                tpa,
                swapchain_texture,
                &render_graph,
                &self.scene,
                &.{ .camera = self.camera.camera, .transform = self.camera.transform },
                self.asset_pool,
            );
        } else {
            _ = try render_graph.addGraphicsPass(
                "Empty Swapchain Pass",
                .{ .color_attachments = &.{.{
                    .texture = swapchain_texture,
                    .clear = .{ 0.25, 0.0, 0.4, 1.0 },
                }} },
                null,
                emptyGraphicsCallback,
            );
        }

        if (IMGUI_ENABLED) {
            const imgui_pass_handle = self.gpu_device.createImguiPass(swapchain_texture, &render_graph);
            _ = imgui_pass_handle; // autofix
        }

        try self.gpu_device.submitRenderGraph(tpa, &render_graph);
    }

    pub fn loadScene(self: *Self, scene_filepath: []const u8, update_camera: bool) !Universe.EntityHandle {
        const tpa = self.temp_allocator.allocator();

        var scene_json: std.json.Parsed(SceneAsset) = undefined;
        {
            var file = try std.fs.cwd().openFile(scene_filepath, .{ .mode = .read_only });
            defer file.close();

            var read_buffer: [1024]u8 = undefined;
            var reader = file.reader(&read_buffer);
            scene_json = try SceneAsset.deserialzie(tpa, &reader.interface);
        }
        defer scene_json.deinit();

        const scene = scene_json.value;

        if (update_camera) {
            if (findFirstNode(&scene, &.{ "Camera", "PhysCamera002" })) |camera_node| {
                if (scene.nodes[camera_node].camera) |node_camera| {
                    self.camera.camera = node_camera;

                    self.camera.transform = scene.calcNodeGlobalTransform(camera_node);
                    self.camera.transform.rotation = zm.qmul(zm.quatFromRollPitchYaw(0.0, std.math.pi, 0.0), self.camera.transform.rotation);

                    //Clamp near/far values
                    self.camera.camera.perspective.far = @min(500, self.camera.camera.perspective.far orelse 500);
                    self.camera.camera.perspective.near = @max(0.1, self.camera.camera.perspective.near);
                }
            }
        }

        const entity = try self.universe2.createEntity(scene.name, self.main_world);
        errdefer self.universe2.destroyEntity(entity.handle);

        entity.nodes = try .initCapacity(self.universe2.gpa, scene.nodes.len);
        for (scene.root_nodes) |root_node| {
            try self.loadNode(&scene, root_node, entity, null);
        }

        self.asset_pool.markAllForLoad();

        return entity.handle;
    }

    fn findFirstNode(scene: *const SceneAsset, names: []const []const u8) ?usize {
        for (names) |name| {
            if (scene.getNodeFromName(name)) |index| {
                return index;
            }
        }
        return null;
    }

    fn loadNode(
        self: *Self,
        scene: *const SceneAsset,
        node_index: usize,
        entity: *Universe.Entity,
        parent_node: ?Universe.NodeHandle,
    ) !void {
        const scene_node = scene.nodes[node_index];

        const node_handle = try entity.createNode(self.universe2.gpa, scene_node.name, parent_node);
        const node = entity.nodes.getPtr(node_handle).?;
        node.local_transform = scene_node.local_transform;

        if (scene_node.mesh) |mesh| {
            const material_handles = try self.allocator.alloc(AssetPool.MaterialAssetHandle, mesh.materials.len);
            defer self.allocator.free(material_handles);

            const mesh_handle = try self.asset_pool.getMeshAsset(mesh.mesh);
            for (material_handles, mesh.materials) |*material_handle, material| {
                material_handle.* = try self.asset_pool.getMaterialAsset(material);
            }

            const global_transform = scene.calcNodeGlobalTransform(node_index);
            node.components.static_mesh = try self.scene.createStaticMeshInstance(true, global_transform, mesh_handle, material_handles);
        }

        for (scene_node.children) |child| {
            try self.loadNode(scene, child, entity, node_handle);
        }
    }

    //Lazy entity update, need to write a better system for this
    // fn updateEntity(self: *Self, entity_handle: Universe.EntityHandle, parent_transform: Transform) void {
    //     const entity = self.universe.entities.getPtr(entity_handle).?;
    //     const global_transform = parent_transform.applyTransform(&entity.local_transform);

    //     if (entity.scene_instance) |scene_instance| {
    //         self.scene.updateStaticMeshInstance(scene_instance, true, global_transform);
    //     }

    //     for (entity.children.slice()) |child| {
    //         self.updateEntity(child, global_transform);
    //     }
    // }
};

const WindowFormatClass = enum {
    @"8bit_unorm",
    @"8bit_srgb",
    @"10_bit",
};

fn getPreferredWindowSettings(window_caps: saturn.WindowCapabilities, usage: saturn.TextureUsage, format_class: WindowFormatClass, vsync: bool) ?saturn.WindowSettings {
    const format: saturn.TextureFormat = switch (format_class) {
        .@"8bit_unorm" => getFirstSupported(saturn.TextureFormat, window_caps.formats, &.{ .bgra8_unorm, .rgba8_unorm }),
        .@"8bit_srgb" => getFirstSupported(saturn.TextureFormat, window_caps.formats, &.{ .bgra8_srgb, .rgba8_srgb }),
        .@"10_bit" => getFirstSupported(saturn.TextureFormat, window_caps.formats, &.{ .bgr10_a2_unorm, .rgb10_a2_unorm }),
    } orelse return null;

    const present_mode = switch (vsync) {
        true => getFirstSupported(saturn.PresentMode, window_caps.present_modes, &.{ .fifo, .mailbox }),
        false => getFirstSupported(saturn.PresentMode, window_caps.present_modes, &.{ .immediate, .mailbox }),
    } orelse return null;

    //TODO: test texture usage

    return .{
        .texture_count = window_caps.min_texture_count,
        .texture_usage = usage,
        .texture_format = format,
        .present_mode = present_mode,
    };
}

fn getFirstSupported(comptime T: type, supported: []const T, desired: []const T) ?T {
    for (desired) |value| {
        if (std.mem.indexOfScalar(T, supported, value)) |_| {
            return value;
        }
    }
    return null;
}

// Window Callbacks
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

// Input Callbacks\
fn gamepadButtonCallback(ctx: ?*anyopaque, gamepad_id: u32, button: saturn.GamepadButton, state: saturn.ButtonState) void {
    _ = gamepad_id; // autofix

    const app: *App = @ptrCast(@alignCast(ctx.?));

    switch (button) {
        .left_shoulder => app.camera.gamepad.shoulder[0] = state.isPressed(),
        .right_shoulder => app.camera.gamepad.shoulder[1] = state.isPressed(),
        else => {},
    }
}

fn gamepadAxisCallback(ctx: ?*anyopaque, gamepad_id: u32, axis: saturn.GamepadAxis, value: f32) void {
    _ = gamepad_id; // autofix

    const app: *App = @ptrCast(@alignCast(ctx.?));

    switch (axis) {
        .left_x => app.camera.gamepad.left_stick[0] = value,
        .left_y => app.camera.gamepad.left_stick[1] = value,
        .right_x => app.camera.gamepad.right_stick[0] = value,
        .right_y => app.camera.gamepad.right_stick[1] = value,
        else => {},
    }
}

fn sceneLoadCallback(userdata: ?*anyopaque, filelist: []const []const u8, filter: ?u32) void {
    _ = filter; // autofix

    if (filelist.len == 0) return;

    const app: *App = @ptrCast(@alignCast(userdata.?));
    std.log.info("sceneLoad: {s}", .{filelist[0]});
    _ = app.loadScene(filelist[0], false) catch |err| std.log.err("Failed to load scene {}", .{err});
}

fn emptyGraphicsCallback(ctx: ?*anyopaque, cmd: saturn.GraphicsCommandEncoder, target_resolution: [2]u32) void {
    _ = ctx; // autofix
    _ = cmd; // autofix
    _ = target_resolution; // autofix
}

fn emptyComputeCallback(ctx: ?*anyopaque, cmd: saturn.ComputeCommandEncoder) void {
    _ = ctx; // autofix
    _ = cmd; // autofix
}

//TODO: abstract and interface for windows
pub const PerformanceWindow = struct {
    name: [:0]const u8 = "Performance",
    open: bool = true,

    average_dt: f32 = 0.0,
    mem_usage: ?usize = null,

    pub fn draw(self: *PerformanceWindow, tpa: std.mem.Allocator) void {
        if (self.open) {
            if (imgui.begin(self.name, &self.open, 0)) {
                imgui.text(std.fmt.allocPrintSentinel(tpa, "Delta Time (ms): {d:.3}", .{self.average_dt * std.time.ms_per_s}, 0) catch "");
                imgui.text(std.fmt.allocPrintSentinel(tpa, "FPS: {d:.3}", .{1.0 / self.average_dt}, 0) catch "");

                if (self.mem_usage) |mem_usage| {
                    imgui.text(std.fmt.allocPrintSentinel(tpa, "Memory Usage: {s}", .{@import("utils.zig").formatBytes(tpa, mem_usage) catch ""}, 0) catch "");
                }

                imgui.end();
            }
        }
    }
};

pub const CameraWindow = struct {
    name: [:0]const u8 = "Camera",
    open: bool = true,

    pub fn draw(self: *CameraWindow, tpa: std.mem.Allocator, camera: *DebugCamera, window_size: [2]u32) void {
        _ = tpa; // autofix
        const width_float: f32 = @floatFromInt(window_size[0]);
        const height_float: f32 = @floatFromInt(window_size[1]);
        const aspect_ratio: f32 = width_float / height_float;

        if (self.open) {
            if (imgui.begin(self.name, &self.open, 0)) {
                var linear_speed = camera.linear_speed[0];
                if (imgui.sliderFloat("Move Speed", &linear_speed, 1, 15)) {
                    camera.linear_speed = @splat(linear_speed);
                }

                switch (camera.camera) {
                    .perspective => |*perspective| {
                        if (imgui.button("Flip Fov Axis")) {
                            perspective.fov = perspective.fov.flip(aspect_ratio);
                        }

                        switch (perspective.fov) {
                            .x => |*x| {
                                _ = imgui.sliderFloat("Fov X", x, 30, 120);
                            },
                            .y => |*y| {
                                _ = imgui.sliderFloat("Fov Y", y, 10, 80);
                            },
                        }

                        // _ = imgui.sliderFloat("Z Near", &perspective.near, 0.0000000001, 1);
                        // if (perspective.far) |*far| {
                        //     _ = imgui.sliderFloat("Z Far", far, 10, 10000);
                        // }
                    },
                    else => {
                        imgui.text("Not implemented for other camera types");
                    },
                }

                var position = zm.vecToArr3(camera.transform.position);
                if (imgui.c.ImGui_InputFloat3("Position", &position)) {
                    camera.transform.position = zm.loadArr3(position);
                }

                var rotation = zm.quatToRollPitchYaw(camera.transform.rotation);
                inline for (&rotation) |*float| float.* = std.math.radiansToDegrees(float.*);
                if (imgui.c.ImGui_InputFloat3("Rotation", &rotation)) {
                    inline for (&rotation) |*float| float.* = std.math.radiansToDegrees(float.*);

                    // Broken :(
                    // camera.transform.rotation = zm.quatFromRollPitchYaw(rotation[0], rotation[1], rotation[2]);
                }

                imgui.end();
            }
        }
    }
};

const SelectedEntityNode = struct {
    entity: Universe.EntityHandle,
    node: ?Universe.NodeHandle = null,
};

pub const SceneWindow = struct {
    const EntityViewType = enum { hierarchy };

    name: [:0]const u8 = "Scene",
    open: bool = true,

    selected_world: ?Universe.WorldHandle = null,
    selected: ?SelectedEntityNode = null,

    entity_view_type: EntityViewType = .hierarchy,

    pub fn draw(self: *SceneWindow, tpa: std.mem.Allocator, universe: *const Universe) void {
        if (self.open) {
            const flags: i32 = imgui.c.ImGuiWindowFlags_MenuBar;
            if (imgui.begin(self.name, &self.open, flags)) {
                if (imgui.beginMenuBar()) {
                    if (imgui.beginMenu("World")) {
                        var iter = universe.worlds.iterator();
                        var count: u32 = 0;
                        while (iter.nextValue()) |world| {
                            count += 1;
                            const is_selected: bool = if (self.selected_world) |sw| world.*.handle.toU64() == sw.toU64() else false;
                            if (imgui.radioButton(world.*.name.?, is_selected)) {
                                self.selected_world = if (is_selected) null else world.*.handle;
                            }
                        }

                        if (count == 0) {
                            imgui.text("No Worlds");
                        }

                        imgui.endMenu();
                    }

                    if (imgui.beginMenu("View")) {
                        const view_types = std.enums.values(EntityViewType);

                        for (view_types) |view_type| {
                            const name = std.enums.tagName(EntityViewType, view_type) orelse "";
                            if (imgui.radioButton(name, self.entity_view_type == view_type)) {
                                self.entity_view_type = view_type;
                            }
                        }

                        imgui.endMenu();
                    }

                    if (imgui.beginMenu("Sort")) {
                        const sort_types: []const [:0]const u8 = &.{"by name"};

                        for (sort_types) |sort_type| {
                            _ = imgui.radioButton(sort_type, true);
                        }

                        imgui.endMenu();
                    }

                    imgui.endMenuBar();
                }

                if (self.selected_world) |selected_world| {
                    switch (self.entity_view_type) {
                        .hierarchy => self.drawEntityHierarchy(tpa, universe, selected_world),
                    }
                }

                imgui.end();
            }
        }

        if (self.selected_world) |selected_world| {
            if (self.selected) |selected| {
                if (universe.entities.get(selected.entity)) |entity| {
                    if (entity.world) |entity_world| {
                        if (entity_world.toU64() != selected_world.toU64()) {
                            self.selected = null;
                        }
                    } else {
                        self.selected = null;
                    }
                }
            }
        } else {
            self.selected = null;
        }
    }

    fn drawEntityHierarchy(self: *SceneWindow, tpa: std.mem.Allocator, universe: *const Universe, selected_world: Universe.WorldHandle) void {
        if (universe.worlds.get(selected_world)) |world| {
            for (world.entities.slice()) |entity_handle| {
                self.drawEntity(tpa, universe, entity_handle);
            }
        }
    }

    fn drawEntity(self: *SceneWindow, tpa: std.mem.Allocator, universe: *const Universe, entity_handle: Universe.EntityHandle) void {
        const entity = universe.entities.get(entity_handle) orelse return;

        var is_selected: bool = false;
        if (self.selected) |selected| {
            if (selected.entity.toU64() == entity.handle.toU64()) {
                is_selected = selected.node == null;
            }
        }
        var flags: i32 = imgui.c.ImGuiTreeNodeFlags_OpenOnDoubleClick | imgui.c.ImGuiTreeNodeFlags_OpenOnArrow;

        if (is_selected) {
            flags |= imgui.c.ImGuiTreeNodeFlags_Selected;
        }

        if (entity.root_nodes.count() == 0) {
            flags |= imgui.c.ImGuiTreeNodeFlags_Leaf;
        }

        var entity_name = entity.name.?;
        if (entity_name.len == 0) {
            entity_name = " ";
        }
        const node_open = imgui.c.ImGui_TreeNodeEx(entity_name, flags);

        if (imgui.c.ImGui_IsItemClicked()) {
            if (is_selected) {
                self.selected = null;
            } else {
                self.selected = .{ .entity = entity_handle };
            }
        }

        if (node_open) {
            for (entity.root_nodes.slice()) |child| {
                self.drawEntityNode(tpa, universe, entity, child);
            }
            imgui.c.ImGui_TreePop();
        }
    }

    fn drawEntityNode(self: *SceneWindow, tpa: std.mem.Allocator, universe: *const Universe, entity: *Universe.Entity, node_handle: Universe.NodeHandle) void {
        var is_selected: bool = false;
        if (self.selected) |selected| {
            if (selected.entity.toU64() == entity.handle.toU64()) {
                if (selected.node) |selected_node| {
                    is_selected = selected_node.toU64() == node_handle.toU64();
                }
            }
        }

        var flags: i32 = imgui.c.ImGuiTreeNodeFlags_OpenOnDoubleClick | imgui.c.ImGuiTreeNodeFlags_OpenOnArrow;

        if (is_selected) {
            flags |= imgui.c.ImGuiTreeNodeFlags_Selected;
        }

        const node = entity.nodes.get(node_handle).?;

        if (node.children.count() == 0) {
            flags |= imgui.c.ImGuiTreeNodeFlags_Leaf;
        }

        var node_name = node.name.?;
        if (node_name.len == 0) {
            node_name = " ";
        }
        const node_open = imgui.c.ImGui_TreeNodeEx(node_name, flags);

        if (imgui.c.ImGui_IsItemClicked()) {
            if (is_selected) {
                self.selected = null;
            } else {
                self.selected = .{
                    .entity = entity.handle,
                    .node = node_handle,
                };
            }
        }

        if (node_open) {
            for (node.children.slice()) |child| {
                self.drawEntityNode(tpa, universe, entity, child);
            }
            imgui.c.ImGui_TreePop();
        }
    }
};

pub const PropertiesWindow = struct {
    name: [:0]const u8 = "Properties",
    open: bool = true,

    pub fn draw(
        self: *PropertiesWindow,
        tpa: std.mem.Allocator,
        universe: *Universe,
        selected_opt: ?SelectedEntityNode,
    ) void {
        _ = tpa; // autofix
        if (self.open) {
            const flags: i32 = 0;
            if (imgui.begin(self.name, &self.open, flags)) {
                if (selected_opt) |selected| {
                    if (selected.node == null) {
                        if (universe.entities.get(selected.entity)) |entity| {
                            imgui.c.ImGui_SeparatorText("Entity");

                            //Name Field
                            {
                                var name_buffer: [256]u8 = @splat(0);
                                if (entity.name) |name| {
                                    @memcpy(name_buffer[0..name.len], name);
                                }

                                if (imgui.inputText("Name", &name_buffer)) {
                                    const index_of = std.mem.indexOfScalar(u8, &name_buffer, 0).?;
                                    const new_name = name_buffer[0..index_of];
                                    universe.gpa.free(entity.name orelse &.{});
                                    entity.name = universe.gpa.dupeZ(u8, new_name) catch @panic("Failed to update entity name");
                                }
                            }

                            //Transform
                            {
                                const header_open = imgui.c.ImGui_CollapsingHeader("Local Transform", imgui.c.ImGuiTreeNodeFlags_DefaultOpen);
                                if (header_open) {
                                    var position = zm.vecToArr3(entity.transform.position);
                                    if (imgui.c.ImGui_InputFloat3("Position", &position)) {
                                        entity.transform.position = zm.loadArr3(position);
                                    }

                                    var rotation = zm.quatToRollPitchYaw(entity.transform.rotation);
                                    inline for (&rotation) |*float| float.* = std.math.radiansToDegrees(float.*);
                                    if (imgui.c.ImGui_InputFloat3("Rotation", &rotation)) {
                                        inline for (&rotation) |*float| float.* = std.math.radiansToDegrees(float.*);
                                        // Broken :(
                                        //entity.transform.rotation = zm.quatFromRollPitchYaw(rotation[0], rotation[1], rotation[2]);
                                    }

                                    var scale = zm.vecToArr3(entity.transform.scale);
                                    if (imgui.c.ImGui_InputFloat3("Scale", &scale)) {
                                        entity.transform.scale = zm.loadArr3(scale);
                                    }
                                }

                                imgui.c.ImGui_SeparatorText("Components");

                                if (imgui.c.ImGui_CollapsingHeader("Model Component", 0)) {
                                    imgui.text("Still under construction 🚧");
                                }
                            }
                        } else {
                            imgui.text("Invalid Entity Selected");
                        }
                    }
                } else {
                    imgui.text("No Entity Selected");
                }

                imgui.end();
            }
        }
    }
};

pub const DemoWindow = struct {
    name: [:0]const u8 = "ImGui Demo",
    open: bool = false,

    pub fn draw(self: *DemoWindow) void {
        if (self.open) {
            imgui.showDemoWindow(&self.open);
        }
    }
};
