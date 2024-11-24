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

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    platform: sdl_platform.Platform,
    rendering_backend: rendering_system.Backend,

    // New World System Test
    game_universe: universe.Universe,
    game_world_handle: universe.World.Handle,
    game_debug_camera: universe.Entity.Handle,

    timer: f32 = 0.0,
    frames: f32 = 0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const platform = try sdl_platform.Platform.init_window(allocator, "Saturn Engine", .{ .windowed = .{ 1920, 1080 } }, .on);

        var rendering_backend = try rendering_system.Backend.init(allocator);
        physics_system.init(allocator);

        var game_universe = try universe.Universe.init(allocator);
        var game_worlds = try world_gen.create_ship_worlds(allocator, &rendering_backend);

        {
            const skybox_base_path = "res/textures/space_skybox_1e1r04uzdb7k/";
            const skybox_paths: [6][:0]const u8 = .{
                skybox_base_path ++ "right.png",

                skybox_base_path ++ "left.png",
                skybox_base_path ++ "top.png",
                skybox_base_path ++ "bottom.png",
                skybox_base_path ++ "front.png",
                skybox_base_path ++ "back.png",
            };

            if (world_gen.load_skybox(&rendering_backend, skybox_paths)) |skybox_handle| {
                game_worlds.outside.systems.render.?.scene.skybox = skybox_handle;
                game_worlds.inside.systems.render.?.scene.skybox = skybox_handle;
            } else |err| {
                std.log.warn("Loading skybox {s} failed with {}", .{ skybox_base_path, err });
            }
        }
        const game_debug_camera = game_worlds.outside.add_entity(try world_gen.create_debug_camera(allocator));

        const outside_world_handle = try game_universe.add_world(game_worlds.outside);
        const inside_world_handle = try game_universe.add_world(game_worlds.inside);
        _ = inside_world_handle; // autofix

        return .{
            .should_quit = false,
            .allocator = allocator,
            .platform = platform,
            .rendering_backend = rendering_backend,

            .game_universe = game_universe,
            .game_world_handle = outside_world_handle,
            .game_debug_camera = game_debug_camera,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_universe.deinit();

        physics_system.deinit();
        self.rendering_backend.deinit();
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

        self.game_universe.update(delta_time);

        var scene: ?*const rendering_system.Scene = null;
        var scene_camera: camera.Camera = .{};

        if (self.game_universe.worlds.get(self.game_world_handle)) |game_world| {
            scene = &game_world.systems.render.?.scene;
            if (game_world.entities.getPtr(self.game_debug_camera)) |game_debug_entity| {
                if (game_debug_entity.systems.debug_camera) |debug_camera_system| {
                    scene_camera.transform = game_debug_entity.get_node_world_transform(debug_camera_system.camera_node.?).?;
                    scene_camera.data = game_debug_entity.node_pool.get(debug_camera_system.camera_node.?).?.components.camera.?;
                }
            }
        }

        self.rendering_backend.clear_framebuffer();
        const window_size = try self.platform.get_window_size();

        if (scene) |scene_ptr| {
            self.rendering_backend.render_scene(window_size, scene_ptr, &scene_camera);
        }

        self.platform.gl_swap_window();
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
