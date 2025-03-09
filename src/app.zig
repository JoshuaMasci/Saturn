const std = @import("std");
const za = @import("zalgebra");

const Platform = @import("platform.zig").getPlatform();
const Window = @import("platform.zig").getWindow();
const RenderThread = @import("rendering/render_thread.zig").RenderThread;

const physics_system = @import("physics");
const zimgui = @import("zimgui");

const input = @import("input.zig");

const world_gen = @import("world_gen.zig");
const Universe = @import("entity/universe.zig");
const World = @import("entity/world.zig");
const Entity = @import("entity/entity.zig");

const global = @import("global.zig");

pub const App = struct {
    const Self = @This();

    should_quit: bool,

    platform: Platform,
    window: Window,
    render_thread: RenderThread,

    game_universe: *Universe,
    game_debug_camera: Entity.Handle,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    pub fn init() !Self {
        try global.assets.addDir("engine", "zig-out/assets");

        var platform = try Platform.init(global.global_allocator);
        const window = platform.createWindow("Saturn Engine", .{ .windowed = .{ 1920, 1080 } });
        const render_thread = try RenderThread.init(global.global_allocator, window);

        physics_system.init(global.global_allocator);
        zimgui.init(global.global_allocator);
        zimgui.backend.init(
            window.handle,
            .{
                .device = render_thread.render_thread_data.renderer.gpu_device,
                .color_target_format = render_thread.render_thread_data.renderer.color_format,
                .msaa_samples = 0, // 1 Sample
            },
        );

        const game_universe = try Universe.init(global.global_allocator);
        const game_worlds = try world_gen.create_ship_worlds(global.global_allocator, game_universe);
        const debug_entity = try world_gen.create_debug_camera(game_universe, game_worlds.inside, .{ .position = za.Vec3.new(0.0, 0.0, -15.0) });
        world_gen.create_props(game_universe, game_worlds.inside, 150, za.Vec3.new(2.5, 0.0, -15.0), 0.15);

        return .{
            .should_quit = false,
            .platform = platform,
            .window = window,
            .render_thread = render_thread,

            .game_universe = game_universe,
            .game_debug_camera = debug_entity,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_universe.deinit();

        physics_system.deinit();

        zimgui.backend.deinit();
        zimgui.deinit();

        self.render_thread.deinit();
        self.platform.destroyWindow(self.window);
        self.platform.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !(self.should_quit or self.platform.should_quit);
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?usize) !void {
        const frame_allocator = global.global_allocator; //TODO: move to arena allocator

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

        try self.platform.proccessEvents(self);

        const input_devices = self.platform.getInputDevices();
        if (input_devices.len > 0) {
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

        //TODO: imgui draw here
        const window_size = self.window.getSize();
        zimgui.backend.newFrame(window_size[0], window_size[1], 1.0);

        if (zimgui.begin("Performance", .{})) {
            zimgui.text("Delta Time {d:.3} ms", .{self.average_dt * 1000});
            zimgui.text("FPS {d:.3}", .{1.0 / self.average_dt});
            if (mem_usage_opt) |mem_usage| {
                if (@import("utils.zig").format_human_readable_bytes(frame_allocator, mem_usage)) |mem_usage_string| {
                    defer frame_allocator.free(mem_usage_string);
                    zimgui.text("Memory Usage {s}", .{mem_usage_string});
                }
            }
        }
        zimgui.end();

        self.render_thread.render_thread_data.scene = null;
        if (self.game_universe.entities.get(self.game_debug_camera)) |game_debug_entity| {
            self.render_thread.render_thread_data.camera_transform = game_debug_entity.transform;

            if (game_debug_entity.world) |game_world| {
                const rendering = @import("entity/engine/rendering.zig");
                if (game_world.systems.get(rendering.RenderWorldSystem)) |render_world| {
                    self.render_thread.render_thread_data.scene = try render_world.scene.dupe(self.render_thread.render_thread_data.temp_allocator.allocator());
                }
            }
        }

        self.render_thread.submitFrame();

        self.game_universe.update(.frame_end, delta_time);
    }

    const DebugCamera = @import("entity/engine/debug_camera.zig").DebugCameraEntitySystem;

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        if (event.button == .renderer_reload and event.state == .pressed) {
            self.render_thread.reload();
            return;
        }

        //std.log.info("Button {} -> {}", .{ event.button, event.state });
        if (self.game_universe.entities.get(self.game_debug_camera)) |game_debug_entity| {
            if (game_debug_entity.systems.get(DebugCamera)) |debug_camera_system| {
                debug_camera_system.on_button_event(event);
            }
        }
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        //std.log.info("Axis {} -> {:.2}", .{ event.axis, event.get_value(false) });
        if (self.game_universe.entities.get(self.game_debug_camera)) |game_debug_entity| {
            if (game_debug_entity.systems.get(DebugCamera)) |debug_camera_system| {
                debug_camera_system.on_axis_event(event);
            }
        }
    }
};
