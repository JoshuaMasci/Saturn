const std = @import("std");
const builtin = @import("builtin");

const zm = @import("zmath");
const zjolt = @import("zjolt");

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

const GameWorld = @import("GameWorld.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true }).init;
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("DebugAllocator has a memory leak!", .{});
    };

    const allocator = debug_allocator.allocator();
    // const allocator = switch (builtin.mode) {
    //      .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    //      .Debug, .ReleaseSafe => debug_allocator.allocator(),
    //  };

    const @"10MB": usize = 1024 * 1024 * 10;
    zjolt.init(allocator, @"10MB", 1);
    defer zjolt.deinit();

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
        const opaque_material_handles: []const AssetPool.MaterialAssetHandle = &.{
            try app.asset_pool.getMaterialAsset(.fromRepoPath("engine", "materials/olive.asset")),
            try app.asset_pool.getMaterialAsset(.fromRepoPath("engine", "materials/purple.asset")),
            try app.asset_pool.getMaterialAsset(.fromRepoPath("engine", "materials/teal.asset")),
        };

        app.asset_pool.markAllForLoad();

        for (0..3) |i| {
            const float_i: f32 = @floatFromInt(i);
            try app.createDynamicCube(
                i,
                .{ .position = .{ 0.0, 3.0 + float_i, 0.0, 0.0 }, .scale = @splat(0.25) },
                cube_mesh_handle,
                opaque_material_handles[@mod(i, opaque_material_handles.len)],
            );
        }

        const sphere_entity_handle = try app.game_world.createEntity("Sphere_Entity", .{ .position = .{ -4.0, 3.0, 0.0, 0.0 } });
        const sphere_entity = app.game_world.getEntity(sphere_entity_handle).?;
        sphere_entity.components.static_mesh = try app.game_world.components.rendering.?.createStaticMeshInstance(
            true,
            sphere_entity.transform,
            sphere_mesh_handle,
            &.{transparent_material_handle},
        );

        const cube_entity_handle = try app.game_world.createEntity("Cube_Entity", .{ .position = .{ -4.0, 3.0, 2.0, 0.0 } });
        const cube_entity = app.game_world.getEntity(cube_entity_handle).?;
        cube_entity.components.static_mesh = try app.game_world.components.rendering.?.createStaticMeshInstance(
            true,
            cube_entity.transform,
            cube_mesh_handle,
            &.{transparent_material_handle},
        );

        const PLAYER_LAYERS: GameWorld.ObjectLayers = .{ .static = true, .dynamic = true, .player = true };
        const player_shape = zjolt.Shape.initSphere(0.25, 1, 13);

        const player_handle = try app.game_world.createEntity("Player", .{ .position = .{ -4.0, 3.0, -5.0, 0.0 } });
        const player_entity = app.game_world.getEntity(player_handle).?;
        player_entity.components.camera = .default;
        player_entity.components.rigid_body = app.game_world.components.physics.?.createAndAddBody(&.{
            .shape = player_shape,
            .position = zm.vecToArr3(player_entity.transform.position),
            .object_layer = PLAYER_LAYERS.toU16(),
            .motion_type = .dynamic,
            .allowed_dofs = .{ .translation_x = true, .translation_y = true, .translation_z = true },
            .allow_sleep = true,
            .gravity_factor = 0.0,
        }, .activate);
        app.player_entity = player_handle;
    }

    try app.loadScene("assets/game/Sponza/NewSponza_Main_glTF_002/scene.json");
    //try app.loadScene("assets/game/Bistro/scene.json");

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

    free_camera: DebugCamera = .{},
    game_world: GameWorld,

    player_entity: ?GameWorld.EntityHandle = null,
    gamepad: @import("Input.zig") = .{},

    temp_allocator: std.heap.ArenaAllocator,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    //Editor Windows
    perf_win: PerformanceWindow = .{},
    scene_win: SceneWindow = .{},
    prop_win: PropertiesWindow = .{},
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

        var game_world: GameWorld = .init(allocator);
        errdefer game_world.deinit();
        game_world.components.rendering = try .init(allocator, gpu_device, asset_pool, 4096);
        game_world.components.physics = .init(.{
            .max_bodies = 1024,
            .num_body_mutexes = 0,
            .max_body_pairs = 1024,
            .max_contact_constraints = 1024,
            .gravity = zjolt.DefaultGravity,
        });

        return .{
            .allocator = allocator,
            .platform = platform,
            .window = window,
            .gpu_device = gpu_device,

            .asset_registry = asset_registry,

            .transfer_queue = transfer_queue,
            .asset_pool = asset_pool,

            .scene_renderer = scene_renderer,

            .game_world = game_world,

            .temp_allocator = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.gpu_device.waitIdle();

        self.temp_allocator.deinit();

        self.game_world.deinit();

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

        if (self.game_world.getEntity(self.player_entity orelse 0)) |player_entity| {
            const linear_speed: zm.Vec = @splat(5);
            const angular_speed: zm.Vec = @splat(std.math.pi);
            const input = self.gamepad.getInput();

            if (player_entity.components.rigid_body) |rigid_body| {
                const linear_velocity = zm.rotate(player_entity.transform.rotation, zm.loadArr3(input.linear) * linear_speed);
                self.game_world.components.physics.?.setBodyLinearVelocity(rigid_body, zm.vecToArr3(linear_velocity));
            }

            //Hijack the movement code from the free-camera for now
            const prev_postion = player_entity.transform.position;
            DebugCamera.applyMovement(delta_time, &player_entity.transform, &self.gamepad, linear_speed, angular_speed);
            player_entity.transform.position = prev_postion; //Reset transform since it will be handled by velocity
        } else {
            self.free_camera.update(delta_time, &self.gamepad);
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
                    _ = imgui.menuItemBool(self.demo_win.name, &self.demo_win.open, true);
                    imgui.endMenu();
                }

                imgui.endMainMenuBar();
            }

            self.perf_win.draw(tpa);
            self.scene_win.draw(tpa, &self.game_world);
            self.prop_win.draw(tpa, &self.game_world, self.scene_win.selected);
            self.demo_win.draw();

            self.platform.endImgui();
        }

        // Game Code Update
        self.game_world.update(delta_time);

        try self.asset_pool.addTransfers(&self.transfer_queue);
        if (self.game_world.components.rendering) |*scene| {
            try scene.addTransfers(&self.transfer_queue);
        }

        var render_graph: saturn.RenderGraph = .init(tpa);
        defer render_graph.deinit();

        try self.transfer_queue.buildPasses(&render_graph);

        const swapchain_texture = try render_graph.acquireWindowTexture(self.window);

        if (true) {
            var camera = self.free_camera.camera;
            var camera_transform = self.free_camera.transform;

            if (self.player_entity) |player_handle| {
                const player_entity = self.game_world.getEntity(player_handle).?;
                camera_transform = player_entity.transform;
                if (player_entity.components.camera) |player_camera| {
                    camera = player_camera;
                }
            }

            const scene = &self.game_world.components.rendering.?;

            try self.scene_renderer.addPasses(
                tpa,
                swapchain_texture,
                &render_graph,
                scene,
                &.{ .camera = camera, .transform = camera_transform },
                self.asset_pool,
            );
        } else {}

        if (IMGUI_ENABLED) {
            const imgui_pass_handle = self.gpu_device.createImguiPass(swapchain_texture, &render_graph);
            _ = imgui_pass_handle; // autofix
        }

        try self.gpu_device.submitRenderGraph(tpa, &render_graph);
    }

    pub fn loadScene(self: *Self, scene_filepath: []const u8) !void {
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

        for (scene.root_nodes) |root_node| {
            try self.loadNode(tpa, &scene, root_node);
        }

        self.asset_pool.markAllForLoad();
    }

    fn loadNode(
        self: *Self,
        tpa: std.mem.Allocator,
        scene: *const SceneAsset,
        node_index: usize,
    ) !void {
        const scene_node = scene.nodes[node_index];

        const global_transform = scene.calcNodeGlobalTransform(node_index);

        const game_entity_handle = try self.game_world.createEntity(scene_node.name, global_transform);
        const game_entity = self.game_world.getEntity(game_entity_handle).?;

        if (scene_node.mesh) |mesh| {
            const material_handles = try self.allocator.alloc(AssetPool.MaterialAssetHandle, mesh.materials.len);
            defer self.allocator.free(material_handles);

            const mesh_handle = try self.asset_pool.getMeshAsset(mesh.mesh);
            for (material_handles, mesh.materials) |*material_handle, material| {
                material_handle.* = try self.asset_pool.getMaterialAsset(material);
            }

            game_entity.components.static_mesh = try self.game_world.components.rendering.?.createStaticMeshInstance(
                true,
                global_transform,
                mesh_handle,
                material_handles,
            );

            if (self.game_world.components.physics) |*world| {
                const LEVEL_LAYERS: GameWorld.ObjectLayers = .{ .static = true };

                const mesh_shape = try self.createMeshShape(tpa, mesh_handle, global_transform.scale);
                //defer mesh_shape.deinit(); //Internally ref counted, can free here

                const body_settings: zjolt.BodySettings = .{
                    .shape = mesh_shape,
                    .allow_sleep = true,
                    .position = zm.vecToArr3(global_transform.position),
                    .rotation = zm.vecToArr4(zm.normalize4(global_transform.rotation)), //TODO: correct quat order?
                    .motion_type = .static,
                    .object_layer = LEVEL_LAYERS.toU16(),
                };
                game_entity.components.rigid_body = world.createAndAddBody(&body_settings, .activate);
            }
        }

        if (scene_node.camera) |camera| {
            game_entity.components.camera = camera;

            switch (game_entity.components.camera.?) {
                .perspective => |*perspective| {
                    //Clamp near/far values
                    perspective.far = @min(500, perspective.far orelse 500);
                    perspective.near = @max(0.1, perspective.near);
                },
                .orthographic => {},
            }
        }

        for (scene_node.children) |child| {
            try self.loadNode(tpa, scene, child);
        }
    }

    fn createMeshShape(self: *const Self, gpa: std.mem.Allocator, mesh_asset: AssetPool.MeshAssetHandle, scale: zm.Vec) !zjolt.Shape {
        const cpu_mesh = self.asset_pool.mesh_assets.get(mesh_asset).?.cpu.?;
        const positions = try gpa.alloc([3]f32, cpu_mesh.vertices.len);
        defer gpa.free(positions);

        for (positions, cpu_mesh.vertices) |*pos, vert| {
            pos.* = zm.vecToArr3(zm.loadArr3(vert.position) * scale);
        }

        if (cpu_mesh.primitives.len == 1) {
            return zjolt.Shape.initMesh(positions, cpu_mesh.indices, 0);
        }

        const sub_shapes = try gpa.alloc(zjolt.SubShapeSettings, cpu_mesh.primitives.len);
        defer {
            for (sub_shapes) |sub_shape| sub_shape.shape.deinit();
            gpa.free(sub_shapes);
        }

        for (sub_shapes, cpu_mesh.primitives, 0..) |*sub_shape, primitive, i| {
            sub_shape.* = .{
                .shape = zjolt.Shape.initMesh(
                    positions[primitive.vertex_offset..(primitive.vertex_offset + primitive.vertex_count)],
                    cpu_mesh.indices[primitive.index_offset..(primitive.index_offset + primitive.index_count)],
                    0,
                ),
                .position = .{ 0, 0, 0 },
                .rotation = .{ 0, 0, 0, 1 },
                .user_data = i,
            };
        }

        return zjolt.Shape.initCompound(sub_shapes, 0);
    }

    fn createDynamicCube(self: *Self, i: usize, transform: Transform, mesh: AssetPool.MeshAssetHandle, material: AssetPool.MaterialAssetHandle) !void {
        const name = try std.fmt.allocPrint(self.allocator, "cube_{}", .{i});
        defer self.allocator.free(name);

        const game_entity_handle = try self.game_world.createEntity(name, transform);
        const game_entity = self.game_world.getEntity(game_entity_handle).?;

        if (self.game_world.components.rendering) |*rendering| {
            game_entity.components.static_mesh = try rendering.createStaticMeshInstance(
                true,
                transform,
                mesh,
                &.{material},
            );
        }

        if (self.game_world.components.physics) |*physics| {
            const OBJECT_LAYERS: GameWorld.ObjectLayers = .{ .static = true, .dynamic = true };

            const cube_shape = zjolt.Shape.initBox(zm.vecToArr3(transform.scale), 1.0, 0);
            defer cube_shape.deinit(); //Internally ref counted, can free here

            const body_settings: zjolt.BodySettings = .{
                .shape = cube_shape,
                .allow_sleep = false,
                .position = zm.vecToArr3(transform.position),
                .rotation = zm.vecToArr4(zm.normalize4(transform.rotation)), //TODO: correct quat order?
                .motion_type = .dynamic,
                .object_layer = OBJECT_LAYERS.toU16(),
            };
            game_entity.components.rigid_body = physics.createAndAddBody(&body_settings, .activate);
        }
    }
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
        .left_shoulder => app.gamepad.shoulder[0] = state.isPressed(),
        .right_shoulder => app.gamepad.shoulder[1] = state.isPressed(),
        else => {},
    }
}

fn gamepadAxisCallback(ctx: ?*anyopaque, gamepad_id: u32, axis: saturn.GamepadAxis, value: f32) void {
    _ = gamepad_id; // autofix

    const app: *App = @ptrCast(@alignCast(ctx.?));

    switch (axis) {
        .left_x => app.gamepad.left_stick[0] = value,
        .left_y => app.gamepad.left_stick[1] = value,
        .right_x => app.gamepad.right_stick[0] = value,
        .right_y => app.gamepad.right_stick[1] = value,
        else => {},
    }
}

fn sceneLoadCallback(userdata: ?*anyopaque, filelist: []const []const u8, filter: ?u32) void {
    _ = filter; // autofix

    if (filelist.len == 0) return;

    const app: *App = @ptrCast(@alignCast(userdata.?));
    std.log.info("sceneLoad: {s}", .{filelist[0]});
    app.loadScene(filelist[0]) catch |err| std.log.err("Failed to load scene {}", .{err});
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

const SelectedEntityNode = struct {
    entity: GameWorld.EntityHandle,
};

pub const SceneWindow = struct {
    const EntityViewType = enum { hierarchy };

    name: [:0]const u8 = "Scene",
    open: bool = true,

    selected: ?GameWorld.EntityHandle = null,

    entity_view_type: EntityViewType = .hierarchy,

    pub fn draw(self: *SceneWindow, tpa: std.mem.Allocator, world: *GameWorld) void {
        if (self.open) {
            const flags: i32 = imgui.c.ImGuiWindowFlags_MenuBar;
            if (imgui.begin(self.name, &self.open, flags)) {
                if (imgui.beginMenuBar()) {
                    if (imgui.beginMenu("World")) {
                        _ = imgui.radioButton("GameWorld", true);
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

                switch (self.entity_view_type) {
                    .hierarchy => self.drawEntityHierarchy(tpa, world),
                }

                imgui.end();
            }
        }

        if (self.selected) |selected| {
            if (world.getEntity(selected) == null) {
                self.selected = null;
            }
        }
    }

    fn drawEntityHierarchy(self: *SceneWindow, tpa: std.mem.Allocator, world: *const GameWorld) void {
        for (world.entities.items) |entity| {
            const is_selected: bool = if (self.selected) |selected| selected == entity.handle else false;

            var name: [:0]const u8 = entity.name orelse std.fmt.allocPrintSentinel(tpa, "Unnamed Entity {}", .{entity.handle}, 0) catch "Unnamed Entity";

            var flags: i32 = imgui.c.ImGuiTreeNodeFlags_OpenOnDoubleClick | imgui.c.ImGuiTreeNodeFlags_OpenOnArrow;

            if (is_selected) {
                flags |= imgui.c.ImGuiTreeNodeFlags_Selected;
            }

            if (true) {
                flags |= imgui.c.ImGuiTreeNodeFlags_Leaf;
            }

            if (name.len == 0) {
                name = " ";
            }
            const node_open = imgui.c.ImGui_TreeNodeEx(name, flags);

            if (imgui.c.ImGui_IsItemClicked()) {
                if (is_selected) {
                    self.selected = null;
                } else {
                    self.selected = entity.handle;
                }
            }

            if (node_open) {
                imgui.c.ImGui_TreePop();
            }
        }
    }
};

pub const PropertiesWindow = struct {
    name: [:0]const u8 = "Properties",
    open: bool = true,

    pub fn draw(
        self: *PropertiesWindow,
        tpa: std.mem.Allocator,
        world: *GameWorld,
        selected_opt: ?GameWorld.EntityHandle,
    ) void {
        _ = tpa; // autofix
        if (self.open) {
            const flags: i32 = 0;
            if (imgui.begin(self.name, &self.open, flags)) {
                if (selected_opt) |selected| {
                    if (world.getEntity(selected)) |entity| {
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
                                if (entity.name) |old| world.gpa.free(old);
                                entity.name = world.gpa.dupeZ(u8, new_name) catch @panic("Failed to update entity name");
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
                        }

                        imgui.c.ImGui_SeparatorText("Components");

                        if (entity.components.static_mesh) |static_mesh| {
                            _ = static_mesh; // autofix
                            if (imgui.c.ImGui_CollapsingHeader("Model Component", 0)) {
                                imgui.text("Still under construction 🚧");
                            }
                        }

                        if (entity.components.camera) |*camera| {
                            if (imgui.c.ImGui_CollapsingHeader("Camera Component", 0)) {
                                switch (camera.*) {
                                    .perspective => |*perspective| {
                                        if (imgui.button("Flip Fov Axis")) {
                                            const fake_aspect_ratio = 1.0;
                                            perspective.fov = perspective.fov.flip(fake_aspect_ratio);
                                        }
                                        switch (perspective.fov) {
                                            .x => |*v| {
                                                const MIN = 30.0;
                                                const MAX = 120.0;
                                                _ = imgui.sliderFloat("Fov X", v, MIN, MAX);
                                                v.* = std.math.clamp(v.*, MIN, MAX);
                                            },
                                            .y => |*v| {
                                                const MIN = 10.0;
                                                const MAX = 80.0;
                                                _ = imgui.sliderFloat("Fov Y", v, MIN, MAX);
                                                v.* = std.math.clamp(v.*, MIN, MAX);
                                            },
                                        }

                                        _ = imgui.sliderFloat("Z Near", &perspective.near, 0.001, 1);
                                        var infinite = perspective.far == null;
                                        if (imgui.checkbox("Infinite Z Far", &infinite)) {
                                            perspective.far = if (perspective.far == null) 100.0 else null;
                                        }
                                        if (perspective.far) |*far| {
                                            _ = imgui.sliderFloat("Z Far", far, 100, 10000);
                                        }
                                    },
                                    .orthographic => |*orthographic| {
                                        _ = orthographic; // autofix
                                        imgui.text("Not implemented for orthographic cameras yet");
                                    },
                                }
                            }
                        }
                    } else {
                        imgui.text("Invalid Entity Selected");
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
