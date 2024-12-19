const std = @import("std");
const za = @import("zalgebra");

//const saturn_options = @import("saturn_options");
const sdl_platform = @import("platform/sdl2.zig");

const rendering_system = @import("rendering.zig");
const physics_system = @import("physics");

const input = @import("input.zig");

const entities = @import("entity.zig");
const world = @import("world.zig");

const camera = @import("camera.zig");
const debug_camera = @import("debug_camera.zig");

const world_gen = @import("world_gen2.zig");

const universe = @import("universe.zig");

//TODO: rename to render system?
const RenderThread = @import("rendering/render_thread.zig").RenderThread;

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    platform: sdl_platform.Platform,
    render_thread: RenderThread,

    // New World System Test
    game_universe: universe.Universe,
    game_world_handle: universe.World.Handle,
    game_debug_camera: universe.Entity.Handle,

    timer: f32 = 0.0,
    frames: f32 = 0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const asset_registry = @import("global.zig").asset_registry;
        try asset_registry.addDirectorySource("engine", "res");

        const platform = try sdl_platform.Platform.init(allocator);
        const render_thread = try RenderThread.init(allocator, .{ .window_name = "Saturn Engine", .size = .{ .windowed = .{ 1920, 1080 } }, .vsync = .on });

        physics_system.init(allocator);

        var game_universe = try universe.Universe.init(allocator);

        var game_worlds = try world_gen.create_ship_worlds(allocator);
        const debug_entity = game_worlds.inside.add_entity(try world_gen.create_debug_camera(allocator));
        const inside_world = try game_universe.add_world(game_worlds.inside);
        const outside_world = try game_universe.add_world(game_worlds.outside);
        _ = outside_world; // autofix

        return .{
            .should_quit = false,
            .allocator = allocator,
            .platform = platform,
            .render_thread = render_thread,

            .game_universe = game_universe,
            .game_world_handle = inside_world,
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
        self.timer += delta_time;
        self.frames += 1;
        if (self.timer > 20.0) {
            const avr_delta_time = self.timer / self.frames;
            std.log.info("DT: {d:.3} ms FPS: {d:.3}", .{ avr_delta_time * 1000, 1.0 / avr_delta_time });
            if (mem_usage_opt) |mem_usage| {
                if (@import("utils.zig").format_human_readable_bytes(self.allocator, mem_usage)) |mem_usage_string| {
                    defer self.allocator.free(mem_usage_string);
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
        if (self.game_universe.worlds.get(self.game_world_handle)) |game_world| {
            if (game_world.systems.render) |render_world| {
                self.render_thread.render_state.scene = &render_world.scene;
            }
        }

        self.render_thread.submitFrame();

        self.game_universe.update(.frame_end, delta_time);
    }

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        //std.log.info("Button {} -> {}", .{ event.button, event.state });
        if (self.game_universe.worlds.get(self.game_world_handle)) |game_world| {
            if (game_world.entities.getPtr(self.game_debug_camera)) |game_debug_entity| {
                if (game_debug_entity.systems.debug_camera) |*debug_camera_system| {
                    debug_camera_system.on_button_event(event);
                }
            }
        }
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        //std.log.info("Axis {} -> {:.2}", .{ event.axis, event.get_value(false) });
        if (self.game_universe.worlds.get(self.game_world_handle)) |game_world| {
            if (game_world.entities.getPtr(self.game_debug_camera)) |game_debug_entity| {
                if (game_debug_entity.systems.debug_camera) |*debug_camera_system| {
                    debug_camera_system.on_axis_event(event);
                }
            }
        }
    }
};
