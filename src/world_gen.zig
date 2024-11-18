const std = @import("std");
const Timer = @import("timer.zig");

const za = @import("zalgebra");

const entities = @import("entity.zig");
const world = @import("world.zig");

const gltf = @import("gltf.zig");
const proc = @import("procedural.zig");

const rendering_system = @import("rendering.zig");
const physics_system = @import("physics");

const Transform = @import("transform.zig");

const zstbi = @import("zstbi");
const OpenglTexture = @import("platform/opengl/texture.zig");
const OpenglMesh = @import("platform/opengl/mesh.zig");
const TexturedVertex = @import("platform/opengl/vertex.zig").TexturedVertex;

pub fn create_planet_world(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend) !world.World {
    var game_world = world.World.init(allocator, rendering_backend);

    const surface_height = 50.0;
    const surface_gravity = 9.8;
    const gravity_stregth = surface_gravity * (surface_height * surface_height);

    const planet_position = za.Vec3.NEG_Y.scale(surface_height);

    // Planet
    const gravity_sphere_volume = try add_sphere(allocator, rendering_backend, &game_world, null, surface_height * 10.0, &.{ .position = planet_position }, false, true, .{ .gravity = true });
    const gravity_sphere_volume_body = game_world.static_entities.getPtr(gravity_sphere_volume.static).?.body.?;
    game_world.physics_world.set_body_gravity_mode_radial(gravity_sphere_volume_body, gravity_stregth);

    // Moon
    const moon_position: za.Vec3 = planet_position.add(za.Vec3.Z.scale(surface_height * 1.5));
    const moon_sphere = try add_sphere(allocator, rendering_backend, &game_world, .{ 0.88, 0.072, 0.76, 1.0 }, 10.0, &.{ .position = moon_position }, true, false, .{ .dynamic = true, .gravity = true });
    const orbital_speed = calc_orbit_speed(planet_position, moon_position, gravity_stregth);
    const orbital_velocity = za.Vec3.new(1.0, 0.75, 0.0).norm().scale(orbital_speed);
    game_world.dynamic_entities.getPtr(moon_sphere.dynamic).?.linear_velocity = orbital_velocity;

    // Test Load
    {
        const file_path = "res/models/planet.glb";
        const load_file = Timer.start();
        var gltf_file = try gltf.load_gltf_file(allocator, file_path);
        defer gltf_file.deinit();
        load_file.end("gltf file load");

        try load_gltf_scene(allocator, &game_world, &gltf_file, rendering_backend);
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

        if (load_skybox(rendering_backend, skybox_paths)) |skybox_handle| {
            game_world.rendering_world.skybox = skybox_handle;
        } else |err| {
            std.log.warn("Loading skybox {s} failed with {}", .{ skybox_base_path, err });
        }
    }

    _ = try add_cube(allocator, rendering_backend, &game_world, .{ 0.0, 1.0, 0.5, 1.0 }, .{0.5} ** 3, &.{ .position = za.Vec3.new(0.0, 1.5, 0.0) }, true, false, .{ .static = true, .dynamic = true, .gravity = true });
    _ = try add_sphere(allocator, rendering_backend, &game_world, .{ 0.5, 1.0, 0.0, 1.0 }, 0.25, &.{ .position = za.Vec3.new(0.5, 1.5, 0.0) }, true, false, .{ .static = true, .dynamic = true, .gravity = true });

    return game_world;
}

fn calc_orbit_speed(gravity_center: za.Vec3, object_pos: za.Vec3, gravity_strength: f32) f32 {
    const distance = gravity_center.sub(object_pos).length();
    const orbital_velocity = @sqrt(gravity_strength / distance);
    const orbital_period = 2.0 * std.math.pi * @sqrt(std.math.pow(f32, distance, 3.0) / gravity_strength);
    std.log.info("orbital_velocity: {d:.3}", .{orbital_velocity});
    std.log.info("orbital_period: {d:.3}s", .{orbital_period});
    return orbital_velocity;
}

pub fn create_flat_world(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend) !world.World {
    var game_world = world.World.init(allocator, rendering_backend);

    const gravity_stregth = 9.8;
    const gravity_vector = za.Vec3.NEG_Y.scale(gravity_stregth);

    const gravity_cube_volume = try add_cube(allocator, rendering_backend, &game_world, null, .{400.0} ** 3, &.{}, false, true, .{ .gravity = true });
    const gravity_cube_volume_body = game_world.static_entities.getPtr(gravity_cube_volume.static).?.body.?;
    game_world.physics_world.set_body_gravity_mode_vector(gravity_cube_volume_body, gravity_vector.toArray());

    // Test Load
    {
        const file_path = "res/models/flat.glb";
        const load_file = Timer.start();
        var gltf_file = try gltf.load_gltf_file(allocator, file_path);
        defer gltf_file.deinit();
        load_file.end("gltf file load");

        try load_gltf_scene(allocator, &game_world, &gltf_file, rendering_backend);
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

        if (load_skybox(rendering_backend, skybox_paths)) |skybox_handle| {
            game_world.rendering_world.skybox = skybox_handle;
        } else |err| {
            std.log.warn("Loading skybox {s} failed with {}", .{ skybox_base_path, err });
        }
    }

    _ = try add_cube(allocator, rendering_backend, &game_world, .{ 1.0, 0.0, 0.5, 1.0 }, .{0.5} ** 3, &.{ .position = za.Vec3.new(0.0, 1.5, 0.0) }, true, false, .{ .static = true, .dynamic = true, .gravity = true });

    return game_world;
}

fn add_cube(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend, game_world: *world.World, color_opt: ?[4]f32, size: [3]f32, transform: *const Transform, dynamic: bool, sensor: bool, layer: world.PhysicsLayer) !world.EntityHandle {
    var mesh_opt: ?entities.EntityRendering = null;
    if (color_opt) |color| {
        const mesh = try proc.create_cube_mesh(allocator, rendering_backend, size);
        const material = try proc.create_color_material(rendering_backend, color);
        mesh_opt = .{
            .mesh = mesh,
            .material = material,
        };
    }

    const shape = physics_system.Shape.init_box(za.Vec3.fromSlice(&size).scale(0.5).toArray(), 1.0);
    //defer shape.deinit();

    return switch (dynamic) {
        true => try game_world.add(entities.DynamicEntity, .{
            .transform = transform.to_unscaled(),
            .physics = .{ .shape = shape, .sensor = sensor, .layer = layer },
            .mesh = mesh_opt,
        }),
        false => try game_world.add(entities.StaticEntity, .{
            .transform = transform.to_unscaled(),
            .physics = .{ .shape = shape, .sensor = sensor, .layer = layer },
            .mesh = mesh_opt,
        }),
    };
}

fn add_sphere(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend, game_world: *world.World, color_opt: ?[4]f32, radius: f32, transform: *const Transform, dynamic: bool, sensor: bool, layer: world.PhysicsLayer) !world.EntityHandle {
    var mesh_opt: ?entities.EntityRendering = null;
    if (color_opt) |color| {
        const mesh = try proc.create_sphere_mesh(allocator, rendering_backend, radius);
        const material = try proc.create_color_material(rendering_backend, color);
        mesh_opt = .{
            .mesh = mesh,
            .material = material,
        };
    }

    const shape = physics_system.Shape.init_sphere(radius, 1.0);
    //defer shape.deinit();

    return switch (dynamic) {
        true => try game_world.add(entities.DynamicEntity, .{
            .transform = transform.to_unscaled(),
            .physics = .{ .shape = shape, .sensor = sensor, .layer = layer },
            .mesh = mesh_opt,
        }),
        false => try game_world.add(entities.StaticEntity, .{
            .transform = transform.to_unscaled(),
            .physics = .{ .shape = shape, .sensor = sensor, .layer = layer },
            .mesh = mesh_opt,
        }),
    };
}

fn load_skybox(rendering_backend: *rendering_system.Backend, file_paths: [6][:0]const u8) !rendering_system.TextureHandle {
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
    const pixel_format: OpenglTexture.PixelFormat = switch (images[0].num_components) {
        1 => .r,
        2 => .rg,
        3 => .rgb,
        4 => .rgba,
        else => unreachable,
    };
    const pixel_type: OpenglTexture.PixelType = .u8;

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

    const texture = OpenglTexture.init_cube(
        size,
        face_data,
        .{
            .load = pixel_format,
            .store = pixel_format,
            .layout = pixel_type,
            .mips = true,
        },
        OpenglTexture.Filtering.linear,
        OpenglTexture.AddressMode.clamp_to_edge,
    );
    return try rendering_backend.load_texture(texture);
}

fn load_gltf_scene(allocator: std.mem.Allocator, game_world: *world.World, gltf_file: *gltf.File, render_backend: *rendering_system.Backend) !void {
    const load_resources = Timer.start();

    var gpu_textures = std.ArrayList(rendering_system.TextureHandle).init(allocator);
    defer gpu_textures.deinit();
    for (gltf_file.textures.items) |texture| {
        try gpu_textures.append(try load_gltf_texture(render_backend, gltf_file.images.items, gltf_file.samplers.items, &texture));
    }

    var gpu_materials = std.ArrayList(rendering_system.MaterialHandle).init(allocator);
    defer gpu_materials.deinit();
    for (gltf_file.materials.items) |material| {
        try gpu_materials.append(try load_gltf_material(render_backend, gpu_textures.items, &material));
    }

    var meshes = std.ArrayList(Mesh).init(allocator);
    defer meshes.deinit();
    for (gltf_file.meshes.items) |mesh| {
        try meshes.append(try load_gltf_mesh(allocator, render_backend, gpu_materials.items, &mesh.?));
    }
    load_resources.end("gltf resource load");

    const load_scene = Timer.start();
    if (gltf_file.default_scene) |default_scene_index| {
        if (gltf_file.scenes.items[default_scene_index]) |*gltf_scene| {
            const root_transform = Transform{};
            for (gltf_scene.root_nodes.items) |root_node| {
                try load_gltf_node(game_world, &root_transform, meshes.items, gltf_scene, root_node);
            }
        }
    }
    load_scene.end("gltf scene load");
}

fn load_gltf_node(game_world: *world.World, parent_transform: *const Transform, gltf_meshes: []const Mesh, gltf_scene: *const gltf.Scene, node_handle: gltf.NodeHandle) !void {
    if (gltf_scene.pool.getPtr(node_handle)) |node| {
        //std.log.info("Node: {s}", .{node.name.items});
        const node_transform_ws = parent_transform.transform_by(&node.transform);

        if (node.mesh) |mesh_index| {
            for (gltf_meshes[mesh_index].primitives.slice()) |primitive| {
                _ = try game_world.add(entities.StaticEntity, .{
                    .transform = node_transform_ws.get_unscaled(),
                    .physics = .{ .shape = primitive.physics_shape, .sensor = false, .layer = .{ .static = true } },
                    .mesh = .{ .mesh = primitive.gpu_mesh, .material = primitive.gpu_material },
                });
            }
        }

        for (node.children.items) |child_node| {
            try load_gltf_node(game_world, &node_transform_ws, gltf_meshes, gltf_scene, child_node);
        }
    }
}

fn load_gltf_texture(render_backend: *rendering_system.Backend, images: []?zstbi.Image, samplers: []gltf.Sampler, gltf_texture: *const gltf.Texture) !rendering_system.TextureHandle {
    const image_index = gltf_texture.image_index orelse return error.NoImageForTexture;

    if (image_index >= images.len) {
        return error.ImageNotLoaded;
    }

    const image = images[image_index] orelse return error.ImageNotLoaded;

    const size: [2]u32 = .{ image.width, image.height };

    const pixel_format: OpenglTexture.PixelFormat = switch (image.num_components) {
        1 => .r,
        2 => .rg,
        3 => .rgb,
        4 => .rgba,
        else => unreachable,
    };

    //Don't support higher bit componets
    if (image.bytes_per_component != 1) {
        return error.UnsupportedImageFormat;
    }

    const pixel_type: OpenglTexture.PixelType = .u8;

    var sampler = OpenglTexture.Sampler{};
    if (gltf_texture.sampler_index) |gltf_sampler_index| {
        const gltf_sampler = samplers[gltf_sampler_index];

        if (gltf_sampler.min) |min_filter| {
            sampler.min = switch (min_filter) {
                .nearest => .nearest,
                .linear => .linear,
                .nearest_mipmap_nearest => .nearest_mipmap_nearest,
                .linear_mipmap_nearest => .linear_mipmap_nearest,
                .nearest_mipmap_linear => .nearest_mipmap_linear,
                .linear_mipmap_linear => .linear_mipmap_linear,
            };
        }

        if (gltf_sampler.mag) |mag_filter| {
            sampler.min = switch (mag_filter) {
                .nearest => .nearest,
                .linear => .linear,
            };
        }

        sampler.address_mode_u = switch (gltf_sampler.address_mode_u) {
            .clamp_to_edge => .clamp_to_edge,
            .mirrored_repeat => .mirrored_repeat,
            .repeat => .repeat,
        };

        sampler.address_mode_u = switch (gltf_sampler.address_mode_v) {
            .clamp_to_edge => .clamp_to_edge,
            .mirrored_repeat => .mirrored_repeat,
            .repeat => .repeat,
        };
    }

    const texture = OpenglTexture.init_2d(
        size,
        image.data,
        .{
            .load = pixel_format,
            .store = pixel_format,
            .layout = pixel_type,
            .mips = true,
        },
        sampler,
    );

    return try render_backend.load_texture(texture);
}

fn load_gltf_material(render_backend: *rendering_system.Backend, textures: []rendering_system.TextureHandle, gltf_material: *const gltf.Material) !rendering_system.MaterialHandle {
    var material: rendering_system.Material = .{};

    material.base_color_factor = gltf_material.base_color_factor;
    if (gltf_material.base_color_texture) |texture| {
        material.base_color_texture = textures[texture.index];
    }

    material.metallic_roughness_factor = gltf_material.metallic_roughness_factor;
    if (gltf_material.metallic_roughness_texture) |texture| {
        material.metallic_roughness_texture = textures[texture.index];
    }

    if (gltf_material.normal_texture) |texture| {
        material.normal_texture = textures[texture.index];
    }

    if (gltf_material.occlusion_texture) |texture| {
        material.occlusion_texture = textures[texture.index];
    }

    material.emissive_factor = gltf_material.emissive_factor;
    if (gltf_material.emissive_texture) |texture| {
        material.emissive_texture = textures[texture.index];
    }

    return try render_backend.load_material(material);
}

pub const Mesh = struct {
    const MAX_PRIMITIVES: usize = 8;
    primitives: std.BoundedArray(Primitive, MAX_PRIMITIVES),
};

pub const Primitive = struct {
    physics_shape: physics_system.Shape,
    gpu_mesh: rendering_system.StaticMeshHandle,
    gpu_material: rendering_system.MaterialHandle,
};

fn load_gltf_mesh(allocator: std.mem.Allocator, render_backend: *rendering_system.Backend, materials: []const rendering_system.MaterialHandle, mesh: *const gltf.Mesh) !Mesh {
    var primitives = try std.BoundedArray(Primitive, Mesh.MAX_PRIMITIVES).init(0);

    for (mesh.primitives.items, 0..@min(mesh.primitives.items.len, Mesh.MAX_PRIMITIVES)) |primitive, _| {
        const physics_shape = physics_system.Shape.init_mesh(primitive.positions.?.items, primitive.indices.?.items);

        const gpu_mesh = try load_gltf_gpu_primitive(allocator, render_backend, &primitive);

        //TODO: get correct default material
        const gpu_material = materials[primitive.default_material_index.?];

        try primitives.append(.{
            .physics_shape = physics_shape,
            .gpu_mesh = gpu_mesh,
            .gpu_material = gpu_material,
        });
    }

    return .{ .primitives = primitives };
}

fn load_gltf_gpu_primitive(
    allocator: std.mem.Allocator,
    render_backend: *rendering_system.Backend,
    primitive: *const gltf.Primitive,
) !rendering_system.StaticMeshHandle {
    var mesh_vertices = try std.ArrayList(TexturedVertex).initCapacity(allocator, primitive.positions.?.items.len);
    defer mesh_vertices.deinit();

    for (primitive.positions.?.items, primitive.normals.?.items, primitive.uv0s.?.items) |position, normal, uv0| {
        mesh_vertices.appendAssumeCapacity(.{
            .position = position,
            .normal = normal,
            .tangent = .{ 0.0, 0.0, 0.0, 1.0 },
            .uv0 = uv0,
        });
    }

    const mesh = OpenglMesh.init(TexturedVertex, u32, mesh_vertices.items, primitive.indices.?.items);
    return try render_backend.static_meshes.insert(mesh);
}
