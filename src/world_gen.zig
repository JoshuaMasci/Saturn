const std = @import("std");
const za = @import("zalgebra");
const world = @import("world.zig");

const gltf = @import("gltf.zig");
const gltf2 = @import("gltf2.zig");
const proc = @import("procedural.zig");

const rendering_system = @import("rendering.zig");
const physics_system = @import("physics");

const Transform = @import("transform.zig");

pub fn create_planet_world(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend) !world.World {
    var game_world = world.World.init(allocator, rendering_backend);

    const surface_height = 50.0;
    const planet_position = za.Vec3.NEG_Y.scale(surface_height + 1.5);

    // Planet
    const planet_sphere = try add_sphere(allocator, rendering_backend, &game_world, .{ 0.412, 1.0, 0.38, 1.0 }, surface_height, &.{ .position = planet_position }, false, false);
    _ = planet_sphere; // autofix
    const planet_sphere_volume = try add_sphere(allocator, rendering_backend, &game_world, null, surface_height * 10.0, &.{ .position = planet_position }, false, true);

    const surface_gravity = 9.8;
    const gravity_stregth = surface_gravity * (surface_height * surface_height);
    game_world.set_planet_gravity_strength(planet_sphere_volume, gravity_stregth);

    // Moon
    const moon_position: za.Vec3 = planet_position.add(planet_position).add(za.Vec3.Z.scale(surface_height * 1.5));
    const moon_sphere = try add_sphere(allocator, rendering_backend, &game_world, .{ 0.88, 0.072, 0.76, 1.0 }, 10.0, &.{ .position = moon_position }, true, false);
    const orbital_velocity = calc_orbit_speed(planet_position, moon_position, gravity_stregth);
    game_world.set_linear_velocity(moon_sphere, za.Vec3.new(orbital_velocity, 0.0, 0.0));

    // Test Load
    {
        const file_path = "res/models/airlock.glb";
        const start = std.time.Instant.now() catch unreachable;
        defer {
            const end = std.time.Instant.now() catch unreachable;
            const time_ns: f32 = @floatFromInt(end.since(start));
            std.log.info("loading gltf file {s} took: {d:.3}ms", .{ file_path, time_ns / std.time.ns_per_ms });
        }
        var gltf_file = try gltf2.load_gltf_file(allocator, file_path);
        defer gltf_file.deinit();

        const shape = physics_system.Shape.init_mesh(gltf_file.meshes.items[0].?.primitives.items[0].positions.?.items, gltf_file.meshes.items[0].?.primitives.items[0].indices.?.items);
        _ = try game_world.add_entity(&.{}, .{ .shape = shape, .dynamic = false }, null);

        try load_gltf_scene2(&game_world, &gltf_file);
    }

    _ = try load_gltf_scene(allocator, rendering_backend, &game_world, "res/models/airlock.glb");

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

        if (load_skybox(rendering_backend, skybox_paths)) |skybox_handle| {
            game_world.rendering_world.skybox = skybox_handle;
        } else |err| {
            std.log.warn("Loading skybox {s} failed with {}", .{ skybox_base_path, err });
        }
    }

    return game_world;
}

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
                .{ .mesh = mesh, .material = material },
            ) catch |err| {
                std.log.err("failed to add scene instance {}", .{err});
            };
        }

        for (node.children.items) |child| {
            load_gltf_node(game_world, resources, scene, child);
        }
    }
}

fn load_gltf_scene2(game_world: *world.World, gltf_file: *gltf2.File) !void {
    // var gltf_file = try gltf2.load_gltf_file(allocator, file_path);
    // defer gltf_file.deinit();

    if (gltf_file.default_scene) |default_scene_index| {
        if (gltf_file.scenes.items[default_scene_index]) |*gltf_scene| {
            const root_transform = Transform{};
            for (gltf_scene.root_nodes.items) |root_node| {
                load_gltf_node2(game_world, &root_transform, gltf_file, gltf_scene, root_node);
            }
        }
    }
}

fn load_gltf_node2(game_world: *world.World, parent_transform: *const Transform, gltf_file: *const gltf2.File, gltf_scene: *const gltf2.Scene, node_handle: gltf2.NodeHandle) void {
    if (gltf_scene.pool.getPtr(node_handle)) |node| {
        std.log.info("Node: {s}", .{node.name.items});
        const node_transform_ws = parent_transform.transform_by(&node.transform);

        for (node.children.items) |child_node| {
            load_gltf_node2(game_world, &node_transform_ws, gltf_file, gltf_scene, child_node);
        }
    }
}

fn calc_orbit_speed(gravity_center: za.Vec3, object_pos: za.Vec3, gravity_strength: f32) f32 {
    const distance = gravity_center.sub(object_pos).length();
    const orbital_velocity = @sqrt(gravity_strength / distance);
    const orbital_period = 2.0 * std.math.pi * @sqrt(std.math.pow(f32, distance, 3.0) / gravity_strength);
    std.log.info("orbital_velocity: {d:.3}", .{orbital_velocity});
    std.log.info("orbital_period: {d:.3}s", .{orbital_period});
    return orbital_velocity;
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
