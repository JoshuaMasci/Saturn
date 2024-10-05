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

    game_world1: world.World,
    game_world2: world.World,

    game_camera: debug_camera.DebugCamera,
    game_cube: physics_system.Shape,

    game_character_world_index: usize = 1,
    game_character: ?world.CharacterPool.Handle,

    fire_ray: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const platform = try sdl_platform.Platform.init_window(allocator, "Saturn Engine", .{ .windowed = .{ 1920, 1080 } }, .on);

        var rendering_backend = try rendering_system.Backend.init(allocator);
        physics_system.init(allocator);

        var game_world1 = try world_gen.create_planet_world(allocator, &rendering_backend);
        const game_world2 = try world_gen.create_flat_world(allocator, &rendering_backend);

        var game_character: ?world.CharacterPool.Handle = null;
        {
            const CharacterHeight: f32 = 0.5;
            const CharacterRadius: f32 = 0.4;

            const shape = physics_system.Shape.init_capsule(CharacterHeight, CharacterRadius, 1.0);
            const shape2 = physics_system.Shape.init_capsule(CharacterHeight - 0.05, CharacterRadius - 0.05, 1.0);

            const character_handle = try game_world1.add(entities.Character, .{
                .transform = .{ .position = za.Vec3.new(0.0, 10.0, 10.0), .rotation = za.Quat.fromAxis(std.math.degreesToRadians(180.0), za.Vec3.Y) },
                .character_shape = shape,
                .body_shape = shape2,
            });
            game_character = character_handle.character;
        }

        return .{
            .should_quit = false,
            .allocator = allocator,

            .platform = platform,

            .game_world1 = game_world1,
            .game_world2 = game_world2,

            .rendering_backend = rendering_backend,
            .game_camera = .{},
            .game_character = game_character,
            .game_cube = physics_system.Shape.init_box(.{1.0} ** 3, 1.0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_world1.deinit();
        self.game_world2.deinit();

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

        self.game_world1.update(delta_time);
        self.game_world2.update(delta_time);

        self.rendering_backend.clear_framebuffer();

        if (self.fire_ray) {
            // if (self.get_active_world().ray_cast(.{ .dynamic = true }, scene_camera.transform.position, scene_camera.transform.get_forward().scale(1000.0))) |hit| {
            //     std.log.info("Raycast Hit: {any:0.3}", .{hit});
            // }

            const src_world = self.get_active_world();
            const dst_world = self.get_other_world();

            if (src_world.shape_cast(self.allocator, .{ .dynamic = true }, self.game_cube, .{ .position = za.Vec3.Y.scale(1.5) })) |hit_list| {
                defer hit_list.deinit();
                std.log.info("ShapeCast Hit: {}", .{hit_list.items.len});

                for (hit_list.items) |hit| {
                    const handle_opt = try moveBetweenWorlds(hit.entity_handle, src_world, dst_world);
                    if (handle_opt) |handle| {
                        switch (handle) {
                            .character => |new_handle| {
                                self.game_character = new_handle;
                                self.flip_world();
                            },
                            else => {},
                        }
                    }

                    // switch (self.game_world1.get_ptr(hit.entity_handle).?) {
                    //     .dynamic => |ptr| {
                    //         ptr.transform.position = ptr.transform.position.add(za.Vec3.Y.scale(10.0));
                    //     },
                    //     .character => |ptr| {
                    //         std.log.info("Char Move", .{});
                    //         ptr.transform.position = ptr.transform.position.add(za.Vec3.Y.scale(10.0));
                    //     },
                    //     else => {},
                    // }
                }
            }

            self.fire_ray = false;
        }

        const scene = &self.get_active_world().rendering_world;
        var scene_camera = camera.Camera{
            .data = self.game_camera.camera,
            .transform = self.game_camera.transform,
        };
        if (self.game_character) |character_handle| {
            if (self.get_active_world().characters.getPtr(character_handle)) |character| {
                scene_camera.transform = character.get_camera_transform().to_scaled(za.Vec3.ONE);
            }
        }

        const window_size = try self.platform.get_window_size();
        self.rendering_backend.render_scene(window_size, scene, &scene_camera);

        {
            imgui.backend.newFrame(try self.platform.get_window_size());

            if (imgui.begin("Performance", .{})) {
                imgui.text("Delta Time {d:.3} ms", .{delta_time * 1000});
                imgui.text("FPS {d:.3}", .{1.0 / delta_time});
                if (mem_usage_opt) |mem_usage| {
                    if (@import("utils.zig").format_human_readable_bytes(self.allocator, mem_usage)) |mem_usage_string| {
                        defer self.allocator.free(mem_usage_string);
                        imgui.text("Memory Usage {s}", .{mem_usage_string});
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
            var character = self.get_active_world().characters.getPtr(character_handle).?;
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
            var character = self.get_active_world().characters.getPtr(character_handle).?;
            character.on_axis_event(event);
        }
    }

    pub fn get_active_world(self: *Self) *world.World {
        return switch (self.game_character_world_index) {
            1 => &self.game_world1,
            2 => &self.game_world2,
            else => undefined,
        };
    }

    pub fn get_other_world(self: *Self) *world.World {
        return switch (self.game_character_world_index) {
            1 => &self.game_world2,
            2 => &self.game_world1,
            else => undefined,
        };
    }

    pub fn flip_world(self: *Self) void {
        self.game_character_world_index = switch (self.game_character_world_index) {
            1 => 2,
            2 => 1,
            else => 1,
        };
    }
};

fn moveBetweenWorlds(handle: world.EntityHandle, src_world: *world.World, dst_world: *world.World) !?world.EntityHandle {
    if (src_world.remove(handle)) |entity| {
        return try dst_world.add_enum_entity(entity);
    }

    return null;
}
