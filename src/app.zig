const std = @import("std");
const za = @import("zalgebra");
const imgui = @import("zimgui");

const sdl_platform = @import("platform/sdl3.zig");
const rendering_system = @import("rendering.zig");
const physics_system = @import("physics");

const input = @import("input.zig");
const world = @import("world.zig");
const Transform = @import("transform.zig");
const camera = @import("camera.zig");
const debug_camera = @import("debug_camera.zig");

const gltf = @import("gltf.zig");
const proc = @import("procedural.zig");

fn calc_orbit_speed(gravity_center: za.Vec3, object_pos: za.Vec3, gravity_strength: f32) f32 {
    const distance = gravity_center.sub(object_pos).length();
    const orbital_velocity = @sqrt(gravity_strength / distance);
    // const orbital_period = 2.0 * std.math.pi * @sqrt(std.math.pow(f32, distance, 3.0) / gravity_strength);
    // std.log.info("orbital_velocity: {d:.3}", .{orbital_velocity});
    // std.log.info("orbital_period: {d:.3}s", .{orbital_period});
    return orbital_velocity;
}

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    platform: sdl_platform.Platform,
    rendering_backend: rendering_system.Backend,

    game_world: world.World,
    game_camera: debug_camera.DebugCamera,
    game_character: ?world.CharacterHandle,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const platform = try sdl_platform.Platform.init_window(allocator, "Saturn Engine", .{ .windowed = .{ 1920, 1080 } }, .on);

        var rendering_backend = try rendering_system.Backend.init(allocator);
        physics_system.init(allocator);

        var game_world = world.World.init(allocator, &rendering_backend);

        var game_character: ?world.CharacterHandle = null;
        {
            const CharacterHeight: f32 = 0.9;
            const CharacterRadius: f32 = 0.5;

            const shape = physics_system.Shape.init_capsule(CharacterHeight, CharacterRadius, 1.0);

            const mesh = try proc.create_capsule_mesh(allocator, &rendering_backend, CharacterHeight, CharacterRadius);
            const material = try proc.create_color_material(&rendering_backend, .{ 1.0, 0.0, 1.0, 1.0 });

            const character_handle = try game_world.add_character(
                &.{ .position = za.Vec3.new(45.0, 55.0, 200.0), .rotation = za.Quat.fromAxis(std.math.degreesToRadians(-90.0), za.Vec3.Y) },
                shape,
                .{ .mesh = mesh, .material = material },
            );
            game_character = character_handle;
        }

        // Cubes
        for (0..100) |i| {
            const cube_position = za.Vec3.new(0.0, @as(f32, @floatFromInt(i)) * 1.2 + 100.0, 200.0);
            _ = try add_cube(
                allocator,
                &rendering_backend,
                &game_world,
                .{ 0.38, 0.412, 1.0, 1.0 },
                .{1.0} ** 3,
                &.{ .position = cube_position, .rotation = za.Quat.new(0.505526, 0.706494, -0.312048, 0.384623) },
                true,
            );
        }

        // Planet
        const planet_sphere = try add_sphere(allocator, &rendering_backend, &game_world, .{ 0.412, 1.0, 0.38, 1.0 }, 50.0, &.{ .position = za.Vec3.new(0.0, 0.0, 200.0) }, false, false);
        const planet_sphere_volume = try add_sphere(allocator, &rendering_backend, &game_world, null, 500.0, &.{ .position = za.Vec3.new(0.0, 0.0, 200.0) }, false, true);
        game_world.set_planet_gravity_strength(planet_sphere_volume, 245000);

        // Moon
        const moon_sphere = try add_sphere(allocator, &rendering_backend, &game_world, .{ 0.88, 0.072, 0.76, 1.0 }, 10.0, &.{ .position = za.Vec3.new(0.0, 0.0, 300.0) }, true, false);
        const orbital_velocity = calc_orbit_speed(za.Vec3.new(0.0, 0.0, 300.0), za.Vec3.new(0.0, 0.0, 200.0), 245000);
        game_world.set_linear_velocity(moon_sphere, za.Vec3.new(orbital_velocity, 0.0, 0.0));

        // Load resources from gltf file
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);
        if (args.len > 1) {
            const file_path = args[1];
            load_gltf_scene(allocator, &rendering_backend, &game_world, file_path) catch |err| {
                std.log.err("Loading {s} failed with {}", .{ file_path, err });
            };
        }

        var game_camera = debug_camera.DebugCamera.Default;
        game_camera.transform.position = za.Vec3.new(45.0, 55.0, 150.0);

        if (game_character) |character_handle| {
            game_world.characters.getPtr(character_handle).?.planet_handle = planet_sphere;
        }

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

            if (load_skybox(&rendering_backend, skybox_paths)) |skybox_handle| {
                game_world.rendering_world.skybox = skybox_handle;
            } else |err| {
                std.log.warn("Loading skybox {s} failed with {}", .{ skybox_base_path, err });
            }
        }

        return .{
            .should_quit = false,
            .allocator = allocator,

            .platform = platform,

            .game_world = game_world,

            .rendering_backend = rendering_backend,
            .game_camera = game_camera,
            .game_character = game_character,
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
        self.platform.proccess_events(self);

        self.game_camera.update(delta_time);
        self.game_world.update(delta_time);

        self.rendering_backend.clear_framebuffer();

        var scene_camera = camera.Camera{
            .data = self.game_camera.camera,
            .transform = self.game_camera.transform,
        };

        // if (self.game_character) |character_handle| {
        //     if (self.game_world.characters.getPtr(character_handle)) |character| {
        //         scene_camera.transform = character.get_camera_transform();
        //     }
        // }

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

fn load_gltf_scene(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend, game_world: *world.World, file_path: [:0]const u8) !void {
    var resources = try gltf.load(allocator, rendering_backend, file_path);
    defer resources.deinit();

    if (resources.default_scene) |default_scene_index| {
        if (resources.scenes.items[default_scene_index]) |*default_scene| {
            for (default_scene.root_nodes.items) |root_node| {
                load_gltf_node(game_world, &resources, default_scene, root_node);
            }
        }
    }
}

fn load_gltf_node(game_world: *world.World, resources: *gltf.Resources, scene: *const gltf.Scene, node_handle: gltf.NodeHandle) void {
    if (scene.pool.getPtr(node_handle)) |node| {
        if (node.model) |model| {
            const mesh = resources.meshes.items[model.mesh].?;
            const material = resources.materials.items[model.materials.items[0]].?;
            _ = game_world.add_entity(
                &node.transform,
                null,
                .{
                    .mesh = mesh,
                    .material = material,
                },
            ) catch |err| {
                std.log.err("failed to add scene instance {}", .{err});
            };
        }

        for (node.children.items) |child| {
            load_gltf_node(game_world, resources, scene, child);
        }
    }
}

fn add_cube(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend, game_world: *world.World, color: [4]f32, size: [3]f32, transform: *const Transform, dynamic: bool) !world.EntityHandle {
    const mesh = try proc.create_cube_mesh(allocator, rendering_backend, size);
    const material = try proc.create_color_material(rendering_backend, color);
    const shape = physics_system.Shape.init_box(za.Vec3.fromSlice(&size).scale(0.5).toArray(), 1.0);
    //defer shape.deinit();
    return game_world.add_entity(
        transform,
        .{ .shape = shape, .dynamic = dynamic },
        .{ .mesh = mesh, .material = material },
    );
}

fn add_sphere(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend, game_world: *world.World, color_opt: ?[4]f32, radius: f32, transform: *const Transform, dynamic: bool, sensor: bool) !world.EntityHandle {
    var model_opt: ?world.Model = null;
    if (color_opt) |color| {
        const mesh = try proc.create_sphere_mesh(allocator, rendering_backend, radius);
        const material = try proc.create_color_material(rendering_backend, color);
        model_opt = .{
            .mesh = mesh,
            .material = material,
        };
    }

    const shape = physics_system.Shape.init_sphere(radius, 1.0);
    //defer shape.deinit();
    return game_world.add_entity(
        transform,
        .{ .shape = shape, .dynamic = dynamic, .sensor = sensor },
        model_opt,
    );
}

fn load_skybox(rendering_backend: *rendering_system.Backend, file_paths: [6][:0]const u8) !rendering_system.TextureHandle {
    const zstbi = @import("zstbi");
    const Texture = @import("platform/opengl/texture.zig");

    var images: [6]zstbi.Image = undefined;
    var face_data: [6][]u8 = undefined;
    for (file_paths, 0..) |file_path, i| {
        images[i] = try zstbi.Image.loadFromFile(file_path, 4);
        face_data[i] = images[i].data;
    }
    defer for (&images) |*image| {
        image.deinit();
    };

    if (images[0].width != images[0].height) {
        return error.image_not_square;
    }

    const size = images[0].width;
    const pixel_format: Texture.PixelFormat = switch (images[0].num_components) {
        1 => .R,
        2 => .RG,
        3 => .RGB,
        4 => .RGBA,
        else => unreachable,
    };
    const pixel_type: Texture.PixelType = .u8;

    for (images[1..]) |image| {
        if (images[0].num_components != image.num_components) {
            return error.inconsistent_image_component_count;
        }

        if (image.bytes_per_component != 1) {
            return error.image_not_8_bit;
        }

        if (image.width != size or image.height != size) {
            return error.inconsistent_image_size;
        }
    }

    const texture = Texture.init_cube(
        size,
        face_data,
        .{
            .load = pixel_format,
            .store = pixel_format,
            .layout = pixel_type,
            .mips = true,
        },
        Texture.Filtering.Linear,
    );
    return try rendering_backend.load_texture(texture);
}
