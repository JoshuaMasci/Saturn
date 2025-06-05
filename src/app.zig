const std = @import("std");

const physics_system = @import("physics");
const Imgui = @import("imgui.zig");
const zm = @import("zmath");

const Entity = @import("entity/entity.zig");
const Universe = @import("entity/universe.zig");
const World = @import("entity/world.zig");
const global = @import("global.zig");
const input = @import("input.zig");
const sdl3 = @import("platform/sdl3.zig");
const PlatformInput = sdl3.Input;
const Window = sdl3.Window;
const RenderThread = @import("rendering/vulkan_render_thread.zig").RenderThread;
const world_gen = @import("world_gen.zig");

pub const App = struct {
    const Self = @This();

    should_quit: bool,

    platform_input: PlatformInput,
    window: Window,
    render_thread: RenderThread,

    imgui: Imgui,

    game_universe: *Universe,
    game_debug_camera: Entity.Handle,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    pub fn init() !Self {
        try global.assets.addDir("engine", "zig-out/assets");
        try global.assets.addDir("game", "zig-out/game-assets");

        try sdl3.init(global.global_allocator);

        const platform_input = try PlatformInput.init(global.global_allocator);
        const window = Window.init("Saturn Engine", .{ .windowed = .{ 1600, 900 } });
        const render_thread = try RenderThread.init(global.global_allocator, window);

        physics_system.init(global.global_allocator);
        //physics_system.initDebugRenderer(render_thread.data.physics_renderer.getDebugRendererData());

        const imgui = try Imgui.init(global.global_allocator);
        errdefer imgui.deinit();

        const game_universe = try Universe.init(global.global_allocator);
        const game_worlds = try world_gen.create_ship_worlds(global.global_allocator, game_universe);
        const debug_entity = try world_gen.create_debug_camera(game_universe, game_worlds.inside, .{ .position = zm.f32x4(0.0, 0.0, -15.0, 0.0) });
        world_gen.create_props(game_universe, game_worlds.inside, 10, zm.f32x4(2.5, 0.0, -15.0, 0.0), 0.15);

        //try world_gen.loadScene(global.global_allocator, game_universe, game_worlds.inside, "zig-out/game-assets/Sponza/NewSponza_Main_glTF_002/scene.json", .{ .position = zm.f32x4(0, -1, 0, 0) });
        //try world_gen.loadScene(global.global_allocator, game_universe, game_worlds.inside, "zig-out/game-assets/Bistro/scene.json", .{ .position = zm.f32x4(0, -50, 0, 0) });

        return .{
            .should_quit = false,
            .platform_input = platform_input,
            .window = window,
            .render_thread = render_thread,
            .imgui = imgui,

            .game_universe = game_universe,
            .game_debug_camera = debug_entity,
        };
    }

    pub fn deinit(self: *Self) void {
        self.render_thread.quit();

        self.game_universe.deinit();

        physics_system.deinitDebugRenderer();
        physics_system.deinit();

        self.imgui.deinit();

        self.render_thread.deinit();
        self.window.deinit();
        self.platform_input.deinit();

        sdl3.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !(self.should_quit or self.platform_input.should_quit);
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?usize) !void {
        const frame_allocator = global.global_allocator; //TODO: move to arena allocator

        {
            self.timer += delta_time;
            self.frames += 1;
            if (self.timer > 5.0) {
                const avr_delta_time = self.timer / self.frames;
                self.average_dt = avr_delta_time;
                self.timer = 0.0;
                self.frames = 0;
                std.log.info("Delta Time {d:.3} ms", .{self.average_dt * 1000});
                if (mem_usage_opt) |mem_usage| {
                    if (@import("utils.zig").format_human_readable_bytes(frame_allocator, mem_usage)) |mem_usage_string| {
                        defer frame_allocator.free(mem_usage_string);
                        std.log.info("Memory Usage {s}", .{mem_usage_string});
                    }
                }
            }
        }

        try self.platform_input.proccessEvents();
        self.imgui.updateInput(&self.platform_input);

        if (!self.platform_input.isMouseCaptured()) {
            if (self.platform_input.isMousePressed(.left)) {
                self.platform_input.captureMouse(self.window);
            }
        }

        //Don't need to check mouse capture since the mouse input device already does that
        const input_devices = self.platform_input.getInputDevices();
        if (input_devices.len > 0) {
            const DebugCamera = @import("entity/engine/debug_camera.zig").DebugCameraEntitySystem;
            const input_context = @import("input_bindings.zig").DebugCameraInputContext.init(input_devices);
            if (self.game_universe.entities.get(self.game_debug_camera)) |game_debug_entity| {
                if (game_debug_entity.systems.get(DebugCamera)) |debug_camera_system| {
                    debug_camera_system.onInput(&input_context);
                }
            }
        }

        self.game_universe.update(.frame_start, delta_time);
        self.game_universe.update(.pre_physics, delta_time);
        self.game_universe.update(.physics, delta_time);
        self.game_universe.update(.post_physics, delta_time);
        self.game_universe.update(.pre_render, delta_time);

        self.render_thread.beginFrame();

        {
            const window_size = self.window.getSize();
            self.imgui.startFrame(window_size, delta_time);

            _ = self.imgui.createFullscreenDockspace("MainDockspace");
            defer Imgui.gui.end();

            // if (zimgui.begin("Performance", .{})) {
            //     zimgui.text("Delta Time {d:.3} ms", .{self.average_dt * 1000});
            //     zimgui.text("FPS {d:.3}", .{1.0 / self.average_dt});
            //     if (mem_usage_opt) |mem_usage| {
            //         if (@import("utils.zig").format_human_readable_bytes(frame_allocator, mem_usage)) |mem_usage_string| {
            //             defer frame_allocator.free(mem_usage_string);
            //             zimgui.text("Memory Usage {s}", .{mem_usage_string});
            //         }
            //     }
            // }
            // zimgui.end();

            // if (!self.platform.isMouseCaptured() and
            //     !zimgui.isWindowHovered(.{ .any_window = true }) and
            //     zimgui.isMouseClicked(zimgui.MouseButton.left) and
            //     !zimgui.isAnyItemHovered())
            // {
            //     self.platform.captureMouse(self.window);
            // }
        }

        self.render_thread.data.scene = null;
        if (self.game_universe.entities.get(self.game_debug_camera)) |game_debug_entity| {
            self.render_thread.data.camera_transform = game_debug_entity.transform;

            if (game_debug_entity.world) |game_world| {
                const rendering = @import("entity/engine/rendering.zig");
                if (game_world.systems.get(rendering.RenderWorldSystem)) |render_world| {
                    self.render_thread.data.scene = try render_world.scene.dupe(self.render_thread.data.temp_allocator.allocator());
                }
            }
        }

        // if (zimgui.begin("Debug", .{})) {
        //     _ = zimgui.checkbox("Debug Physics Layer", .{ .v = &self.render_thread.data.physics_renderer.enabled });
        // }
        // zimgui.end();
        // if (self.render_thread.data.physics_renderer.enabled) {
        //     if (self.game_universe.entities.get(self.game_debug_camera)) |game_debug_entity| {
        //         if (game_debug_entity.world) |game_world| {
        //             const physics = @import("entity/engine/physics.zig");
        //             if (game_world.systems.get(physics.PhysicsWorldSystem)) |physics_world| {
        //                 self.render_thread.data.physics_renderer.buildFrame(&physics_world.physics_world, .{});
        //             }
        //         }
        //     }
        //}

        //TODO: actually render the frame
        self.imgui.render();

        self.render_thread.submitFrame();

        self.game_universe.update(.frame_end, delta_time);
    }
};
