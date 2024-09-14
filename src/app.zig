const std = @import("std");
const za = @import("zalgebra");
const imgui = @import("zimgui");

const saturn_options = @import("saturn_options");
const sdl_platform = if (saturn_options.sdl3) @import("platform/sdl3.zig") else @import("platform/sdl2.zig");

const rendering_system = @import("rendering.zig");
const physics_system = @import("physics");

const input = @import("input.zig");

const entities = @import("entity.zig");
const world = @import("world.zig");

const camera = @import("camera.zig");
const debug_camera = @import("debug_camera.zig");

const world_gen = @import("world_gen.zig");

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    platform: sdl_platform.Platform,
    rendering_backend: rendering_system.Backend,

    game_world: world.World,
    game_camera: debug_camera.DebugCamera,
    game_character: ?world.CharacterPool.Handle,
    game_cube: physics_system.Shape,

    fire_ray: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const platform = try sdl_platform.Platform.init_window(allocator, "Saturn Engine", .{ .windowed = .{ 1920, 1080 } }, .on);

        var rendering_backend = try rendering_system.Backend.init(allocator);
        physics_system.init(allocator);

        var game_world = try world_gen.create_planet_world(allocator, &rendering_backend);

        var game_character: ?world.CharacterPool.Handle = null;
        {
            const CharacterHeight: f32 = 0.5;
            const CharacterRadius: f32 = 0.4;

            const shape = physics_system.Shape.init_capsule(CharacterHeight, CharacterRadius, 1.0);

            const character_handle = try game_world.add(entities.Character, .{
                .transform = .{ .position = za.Vec3.new(0.0, 0.0, 25.0), .rotation = za.Quat.fromAxis(std.math.degreesToRadians(180.0), za.Vec3.Y) },
                .physics_shape = shape,
            });
            game_character = character_handle.character;
        }

        var game_camera: debug_camera.DebugCamera = .{};
        game_camera.transform.position = za.Vec3.new(45.0, 55.0, 150.0);
        game_camera.camera.far = 10_000.0;

        return .{
            .should_quit = false,
            .allocator = allocator,

            .platform = platform,

            .game_world = game_world,

            .rendering_backend = rendering_backend,
            .game_camera = game_camera,
            .game_character = game_character,
            .game_cube = physics_system.Shape.init_box(.{1.0} ** 3, 1.0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_world.deinit();

        physics_system.deinit();
        self.rendering_backend.deinit();
        self.platform.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !(self.should_quit or self.platform.should_quit);
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?usize) !void {
        try self.platform.proccess_events(self);

        self.game_camera.update(delta_time);
        self.game_world.update(delta_time);

        self.rendering_backend.clear_framebuffer();

        var scene_camera = camera.Camera{
            .data = self.game_camera.camera,
            .transform = self.game_camera.transform,
        };

        if (self.game_character) |character_handle| {
            if (self.game_world.characters.getPtr(character_handle)) |character| {
                scene_camera.transform = character.get_camera_transform().to_scaled(za.Vec3.ONE);
            }
        }

        if (self.fire_ray) {
            if (self.game_world.cast_ray(1, scene_camera.transform.position, scene_camera.transform.get_forward().scale(1000.0))) |hit| {
                std.log.info("Raycast Hit: {any:0.3}", .{hit});
            }
            self.fire_ray = false;
        }

        const window_size = try self.platform.get_window_size();
        self.rendering_backend.render_scene(window_size, &self.game_world.rendering_world, &scene_camera);

        {
            imgui.backend.newFrame(try self.platform.get_window_size());

            if (imgui.begin("Performance", .{})) {
                imgui.text("Delta Time {d:.3}", .{delta_time * 1000});
                imgui.text("FPS {d:.3}", .{1.0 / delta_time});
                if (mem_usage_opt) |mem_usage| {
                    const mem_usage_string_opt: ?[]u8 = @import("utils.zig").format_human_readable_bytes(self.allocator, mem_usage) catch null;
                    if (mem_usage_string_opt) |mem_usage_string| {
                        imgui.text("Memory Usage {s}", .{mem_usage_string});
                        self.allocator.free(mem_usage_string);
                    }
                }
            }
            imgui.end();

            imgui.backend.draw();
        }
        self.platform.gl_swap_window();
    }

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        //std.log.info("Button {} -> {}", .{ event.button, event.state });
        self.game_camera.on_button_event(event);

        if (self.game_character) |character_handle| {
            var character = self.game_world.characters.getPtr(character_handle).?;
            character.on_button_event(event);
        }

        if (event.button == .debug_camera_interact and event.state == .pressed) {
            self.fire_ray = true;
        }
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        //std.log.info("Axis {} -> {:.2}", .{ event.axis, event.get_value(false) });
        self.game_camera.on_axis_event(event);

        if (self.game_character) |character_handle| {
            var character = self.game_world.characters.getPtr(character_handle).?;
            character.on_axis_event(event);
        }
    }
};
