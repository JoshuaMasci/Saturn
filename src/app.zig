const std = @import("std");
const za = @import("zalgebra");

//const saturn_options = @import("saturn_options");
const sdl_platform = @import("platform/sdl2.zig");

const physics_system = @import("physics");
const RenderThread = @import("rendering/render_thread.zig").RenderThread;
const input = @import("input.zig");

const world_gen = @import("world_gen.zig");
const Universe = @import("entity/universe.zig");
const World = @import("entity/world.zig");
const Entity = @import("entity/entity.zig");

const global = @import("global.zig");

pub const App = struct {
    const Self = @This();

    should_quit: bool,

    platform: sdl_platform.Platform,
    render_thread: RenderThread,

    // New World System Test
    game_universe: Universe,
    game_debug_camera: Entity.Handle,

    timer: f32 = 0,
    frames: f32 = 0,

    pub fn init() !Self {
        try global.assets.addDir("engine", "zig-out/assets");

        const platform = try sdl_platform.Platform.init(global.global_allocator);
        const render_thread = try RenderThread.init(global.global_allocator, .{ .window_name = "Saturn Engine", .size = .{ .windowed = .{ 1920, 1080 } }, .vsync = .on });

        physics_system.init(global.global_allocator);

        var game_universe = try Universe.init(global.global_allocator);

        const game_worlds = try world_gen.create_ship_worlds(global.global_allocator, &game_universe);
        const debug_entity = try world_gen.create_debug_camera(&game_universe, game_worlds.inside);

        return .{
            .should_quit = false,
            .platform = platform,
            .render_thread = render_thread,

            .game_universe = game_universe,
            .game_debug_camera = debug_entity,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_universe.deinit();

        physics_system.deinit();

        self.render_thread.deinit();
        self.platform.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !(self.should_quit or self.platform.should_quit);
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?usize) !void {
        const frame_allocator = global.global_allocator; //TODO: move to arena allocator

        self.timer += delta_time;
        self.frames += 1;
        if (self.timer > 20.0) {
            const avr_delta_time = self.timer / self.frames;
            std.log.info("DT: {d:.3} ms FPS: {d:.3}", .{ avr_delta_time * 1000, 1.0 / avr_delta_time });
            if (mem_usage_opt) |mem_usage| {
                if (@import("utils.zig").format_human_readable_bytes(frame_allocator, mem_usage)) |mem_usage_string| {
                    defer frame_allocator.free(mem_usage_string);
                    std.log.info("Mem Usage: {s}", .{mem_usage_string});
                }
            }
            self.timer = 0.0;
            self.frames = 0;
        }

        try self.platform.proccess_events(self);

        self.game_universe.update(.frame_start, delta_time);
        self.game_universe.update(.pre_physics, delta_time);
        self.game_universe.update(.physics, delta_time);
        self.game_universe.update(.post_physics, delta_time);
        self.game_universe.update(.pre_render, delta_time);

        self.render_thread.beginFrame();

        self.render_thread.render_state.scene = null;
        if (self.game_universe.entites.get(self.game_debug_camera)) |game_debug_entity| {
            self.render_thread.render_state.camera_transform = game_debug_entity.transform;

            if (game_debug_entity.world_handle) |world_handle| {
                if (self.game_universe.worlds.get(world_handle)) |game_world| {
                    const rendering = @import("entity/engine/rendering.zig");
                    if (game_world.systems.get(rendering.RenderWorldSystem)) |render_world| {
                        self.render_thread.render_state.scene = try render_world.scene.dupe(self.render_thread.render_state.temp_allocator.allocator());
                    }
                }
            }
        }

        self.render_thread.submitFrame();

        self.game_universe.update(.frame_end, delta_time);
    }

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        if (event.button == .renderer_reload and event.state == .pressed) {
            self.render_thread.reload();
            return;
        }

        //std.log.info("Button {} -> {}", .{ event.button, event.state });
        if (self.game_universe.entites.get(self.game_debug_camera)) |game_debug_entity| {
            if (game_debug_entity.systems.debug_camera) |*debug_camera_system| {
                debug_camera_system.on_button_event(event);
            }
        }
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        //std.log.info("Axis {} -> {:.2}", .{ event.axis, event.get_value(false) });
        if (self.game_universe.entites.get(self.game_debug_camera)) |game_debug_entity| {
            if (game_debug_entity.systems.debug_camera) |*debug_camera_system| {
                debug_camera_system.on_axis_event(event);
            }
        }
    }
};
