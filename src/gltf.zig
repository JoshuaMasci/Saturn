const std = @import("std");
const za = @import("zalgebra");

const zgltf = @import("zgltf");

const zstbi = @import("zstbi");

const rendering_system = @import("rendering.zig");

const TexturedVertex = @import("platform/opengl/vertex.zig").TexturedVertex;
const Texture = @import("platform/opengl/texture.zig");
const Mesh = @import("platform/opengl/mesh.zig");

const Transform = @import("transform.zig");
const object_pool = @import("object_pool.zig");

pub const Resources = struct {
    textures: std.ArrayList(?rendering_system.TextureHandle),
    materials: std.ArrayList(?rendering_system.MaterialHandle),
    meshes: std.ArrayList(?rendering_system.StaticMeshHandle),
    scenes: std.ArrayList(?Scene),

    default_scene: ?usize,

    pub fn deinit(self: *@This()) void {
        self.textures.deinit();
        self.materials.deinit();
        self.meshes.deinit();

        for (self.scenes.items) |*scene_opt| {
            if (scene_opt.*) |*scene| {
                scene.deinit();
            }
        }

        self.scenes.deinit();
    }
};

pub const Model = struct {
    mesh: usize,
    materials: std.ArrayList(usize),
};

const NodePool = object_pool.ObjectPool(u16, Node);
pub const NodeHandle = NodePool.Handle;
const NodeHandleArrayList = std.ArrayList(NodeHandle);

pub const Node = struct {
    transform: Transform = .{},
    model: ?Model = null,
    camera: ?void = null,
    light: ?void = null,

    children: NodeHandleArrayList,

    pub fn deinit(self: *@This()) void {
        if (self.model) |model| {
            model.materials.deinit();
        }

        self.children.deinit();
    }
};

pub const Scene = struct {
    const Self = @This();

    pool: NodePool,
    root_nodes: NodeHandleArrayList,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .pool = NodePool.init(allocator),
            .root_nodes = NodeHandleArrayList.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.pool.deinit_with_entries();
        self.root_nodes.deinit();
    }
};

pub fn load(allocator: std.mem.Allocator, renderer: *rendering_system.Backend, file_path: [:0]const u8) !Resources {
    const start = std.time.Instant.now() catch unreachable;
    defer {
        const end = std.time.Instant.now() catch unreachable;
        const time_ns: f32 = @floatFromInt(end.since(start));
        std.log.info("loading file {s} took: {d:.3}ms", .{ file_path, time_ns / std.time.ns_per_ms });
    }

    const parent_path = std.fs.path.dirname(file_path) orelse ".";

    var gltf_file = zgltf.init(allocator);
    defer gltf_file.deinit();

    const file_buffer = try std.fs.cwd().readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
    defer allocator.free(file_buffer);
    try gltf_file.parse(file_buffer);

    var images = try std.ArrayList(?zstbi.Image).initCapacity(allocator, gltf_file.data.images.items.len);
    defer {
        for (images.items) |*image_opt| {
            if (image_opt.*) |*image| {
                image.deinit();
            }
        }
        images.deinit();
    }

    for (gltf_file.data.images.items, 0..) |*glft_image, i| {
        if (load_gltf_image(allocator, parent_path, glft_image)) |image_opt| {
            images.appendAssumeCapacity(image_opt);
        } else |err| {
            std.log.err("Failed to load {s} image {}: {}", .{ file_path, i, err });
            images.appendAssumeCapacity(null);
        }
    }

    var textures = try std.ArrayList(?rendering_system.TextureHandle).initCapacity(allocator, gltf_file.data.textures.items.len);
    for (gltf_file.data.textures.items, 0..) |gltf_texture, i| {
        if (load_gltf_texture(renderer, images.items, gltf_file.data.samplers.items, &gltf_texture)) |texture| {
            textures.appendAssumeCapacity(texture);
        } else |err| {
            std.log.err("Failed to load {s} texture {}: {}", .{ file_path, i, err });
            textures.appendAssumeCapacity(null);
        }
    }

    var materials = try std.ArrayList(?rendering_system.MaterialHandle).initCapacity(allocator, gltf_file.data.materials.items.len);
    for (gltf_file.data.materials.items, 0..) |gltf_material, i| {
        if (load_gltf_material(renderer, textures.items, &gltf_material)) |material| {
            materials.appendAssumeCapacity(material);
        } else |err| {
            std.log.err("Failed to load {s} material {}: {}", .{ file_path, i, err });
            materials.appendAssumeCapacity(null);
        }
    }

    var meshes = try std.ArrayList(?rendering_system.StaticMeshHandle).initCapacity(allocator, gltf_file.data.meshes.items.len);
    for (gltf_file.data.meshes.items, 0..) |*glft_mesh, i| {
        if (load_gltf_mesh(allocator, renderer, &gltf_file, glft_mesh)) |mesh_opt| {
            meshes.appendAssumeCapacity(mesh_opt);
        } else |err| {
            std.log.err("Failed to load {s} mesh {}: {}", .{ file_path, i, err });
            meshes.appendAssumeCapacity(null);
        }
    }

    var scenes = try std.ArrayList(?Scene).initCapacity(allocator, gltf_file.data.scenes.items.len);
    for (gltf_file.data.scenes.items) |gltf_scene| {
        if (load_gltf_scene(allocator, &gltf_file.data, &gltf_scene)) |scene| {
            scenes.appendAssumeCapacity(scene);
        } else |err| {
            std.log.err("Failed to load {s} scene {s}: {}", .{ file_path, gltf_scene.name, err });
            scenes.appendAssumeCapacity(null);
        }
    }

    return .{
        .textures = textures,
        .materials = materials,
        .meshes = meshes,
        .scenes = scenes,
        .default_scene = gltf_file.data.scene,
    };
}

fn load_gltf_image(allocator: std.mem.Allocator, parent_path: []const u8, gltf_image: *const zgltf.Image) !?zstbi.Image {
    if (gltf_image.data) |data| {
        return try zstbi.Image.loadFromMemory(data, 0);
    }

    if (gltf_image.uri) |uri| {
        var full_path = std.ArrayList(u8).init(allocator);
        defer full_path.deinit();
        try full_path.appendSlice(parent_path);
        try full_path.append('/');
        try full_path.appendSlice(uri);
        try full_path.append(0);
        return try zstbi.Image.loadFromFile(full_path.items[0..(full_path.items.len - 1) :0], 4);
    }
    std.log.err("gltf image doesn't contain a source (either buffer view or uri)", .{});
    return null;
}

fn load_gltf_texture(renderer: *rendering_system.Backend, images: []?zstbi.Image, samplers: []zgltf.TextureSampler, gltf_texture: *const zgltf.Texture) !rendering_system.TextureHandle {
    const image_index = gltf_texture.source orelse return error.NoImageForTexture;

    if (image_index >= images.len) {
        return error.ImageNotLoaded;
    }

    const image = images[image_index] orelse return error.ImageNotLoaded;

    const size: [2]u32 = .{ image.width, image.height };

    const pixel_format: Texture.PixelFormat = switch (image.num_components) {
        1 => .R,
        2 => .RG,
        3 => .RGB,
        4 => .RGBA,
        else => unreachable,
    };

    //Don't support higher bit componets
    if (image.bytes_per_component != 1) {
        return error.UnsupportedImageFormat;
    }

    const pixel_type: Texture.PixelType = .u8;

    var sampler = Texture.Sampler{};
    if (gltf_texture.sampler) |gltf_sampler_index| {
        const gltf_sampler = samplers[gltf_sampler_index];

        if (gltf_sampler.min_filter) |min_filter| {
            sampler.min = switch (min_filter) {
                .nearest => .Nearest,
                .linear => .Linear,
                .nearest_mipmap_nearest => .Nearest_Mip_Nearest,
                .linear_mipmap_nearest => .Linear_Mip_Nearest,
                .nearest_mipmap_linear => .Nearest_Mip_Linear,
                .linear_mipmap_linear => .Linear_Mip_Linear,
            };
        }

        if (gltf_sampler.mag_filter) |mag_filter| {
            sampler.min = switch (mag_filter) {
                .nearest => .Nearest,
                .linear => .Linear,
            };
        }

        sampler.address_mode_u = switch (gltf_sampler.wrap_s) {
            .clamp_to_edge => .Clamp_To_Edge,
            .mirrored_repeat => .Mirrored_Repeat,
            .repeat => .Repeat,
        };

        sampler.address_mode_u = switch (gltf_sampler.wrap_t) {
            .clamp_to_edge => .Clamp_To_Edge,
            .mirrored_repeat => .Mirrored_Repeat,
            .repeat => .Repeat,
        };
    }

    const texture = Texture.init_2d(
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

    return try renderer.load_texture(texture);
}

fn load_gltf_material(renderer: *rendering_system.Backend, textures: []?rendering_system.TextureHandle, gltf_material: *const zgltf.Material) !rendering_system.MaterialHandle {
    var material: rendering_system.Material = .{};

    material.base_color_factor = gltf_material.metallic_roughness.base_color_factor;
    if (gltf_material.metallic_roughness.base_color_texture) |texture| {
        material.base_color_texture = textures[texture.index];
    }

    material.metallic_roughness_factor = .{ gltf_material.metallic_roughness.metallic_factor, gltf_material.metallic_roughness.roughness_factor };
    if (gltf_material.metallic_roughness.metallic_roughness_texture) |texture| {
        material.metallic_roughness_texture = textures[texture.index];
    }

    if (gltf_material.normal_texture) |texture| {
        material.normal_texture = textures[texture.index];
    }

    if (gltf_material.occlusion_texture) |texture| {
        material.occlusion_texture = textures[texture.index];
    }

    material.emissive_factor = gltf_material.emissive_factor;
    material.emissive_factor[0] *= gltf_material.emissive_strength;
    material.emissive_factor[1] *= gltf_material.emissive_strength;
    material.emissive_factor[2] *= gltf_material.emissive_strength;

    if (gltf_material.emissive_texture) |texture| {
        material.emissive_texture = textures[texture.index];
    }

    return try renderer.load_material(material);
}

//TODO: load mesh as indvidial primitives
pub fn load_gltf_mesh(allocator: std.mem.Allocator, renderer: *rendering_system.Backend, gltf_file: *const zgltf, gltf_mesh: *const zgltf.Mesh) !rendering_system.StaticMeshHandle {
    var mesh_indices = std.ArrayList(u32).init(allocator);
    defer mesh_indices.deinit();

    var mesh_positions = std.ArrayList([3]f32).init(allocator);
    defer mesh_positions.deinit();

    var mesh_normals = std.ArrayList([3]f32).init(allocator);
    defer mesh_normals.deinit();

    var mesh_tangents = std.ArrayList([4]f32).init(allocator);
    defer mesh_tangents.deinit();

    var mesh_uv0s = std.ArrayList([2]f32).init(allocator);
    defer mesh_uv0s.deinit();

    for (gltf_mesh.primitives.items) |*primitive| {
        try appendMeshPrimitive(
            gltf_file,
            primitive,
            &mesh_indices,
            &mesh_positions,
            &mesh_normals,
            &mesh_uv0s,
            &mesh_tangents,
        );
    }

    var mesh_vertices = try std.ArrayList(TexturedVertex).initCapacity(allocator, mesh_positions.items.len);
    defer mesh_vertices.deinit();

    // create fake tangents if none are provided
    //TODO: calc tangents if not provided
    if (mesh_tangents.items.len == 0) {
        try mesh_tangents.appendNTimes(.{ 0.0, 0.0, 0.0, 0.0 }, mesh_positions.items.len);
    }

    for (mesh_positions.items, mesh_normals.items, mesh_tangents.items, mesh_uv0s.items) |position, normal, tangent, uv0| {
        mesh_vertices.appendAssumeCapacity(.{
            .position = position,
            .normal = normal,
            .tangent = tangent,
            .uv0 = uv0,
        });
    }

    const mesh = Mesh.init(TexturedVertex, u32, mesh_vertices.items, mesh_indices.items);
    return try renderer.static_meshes.insert(mesh);
}

pub fn load_gltf_scene(allocator: std.mem.Allocator, gltf_data: *const zgltf.Data, gltf_scene: *const zgltf.Scene) !Scene {
    var scene = Scene.init(allocator);

    if (gltf_scene.nodes) |root_nodes| {
        for (root_nodes.items) |child_node_index| {
            try scene.root_nodes.append(try add_gltf_node(
                &scene,
                allocator,
                gltf_data,
                &gltf_data.nodes.items[child_node_index],
            ));
        }
    }

    return scene;
}

fn add_gltf_node(scene: *Scene, allocator: std.mem.Allocator, gltf_data: *const zgltf.Data, gltf_node: *const zgltf.Node) !NodeHandle {
    var node: Node = .{
        .children = try NodeHandleArrayList.initCapacity(allocator, gltf_node.children.items.len),
    };

    node.transform.position = za.Vec3.fromArray(gltf_node.translation);
    node.transform.rotation = za.Quat.fromArray(gltf_node.rotation);
    node.transform.scale = za.Vec3.fromArray(gltf_node.scale);

    //TODO: if has_matrix decompose mat4 to transform
    // std.debug.assert(gltf_node.matrix == null);

    if (gltf_node.mesh) |gltf_mesh_index| {
        const gltf_mesh = gltf_data.meshes.items[gltf_mesh_index];

        if (gltf_mesh.primitives.items[0].material) |material| {
            if (gltf_data.materials.items[material].alpha_mode == .@"opaque") {
                var materials = try std.ArrayList(usize).initCapacity(allocator, gltf_mesh.primitives.items.len);
                for (gltf_mesh.primitives.items) |gltf_primitive| {
                    materials.appendAssumeCapacity(gltf_primitive.material.?);
                }
                node.model = .{ .mesh = gltf_mesh_index, .materials = materials };
            }
        }
    }

    for (gltf_node.children.items) |child_node_index| {
        node.children.appendAssumeCapacity(try add_gltf_node(
            scene,
            allocator,
            gltf_data,
            &gltf_data.nodes.items[child_node_index],
        ));
    }

    return try scene.pool.insert(node);
}

pub fn appendMeshPrimitive(
    gltf_file: *const zgltf,
    primitive: *const zgltf.Primitive,
    indices: *std.ArrayList(u32),
    positions: *std.ArrayList([3]f32),
    normals: ?*std.ArrayList([3]f32),
    texcoords0: ?*std.ArrayList([2]f32),
    tangents: ?*std.ArrayList([4]f32),
) !void {
    if (primitive.indices) |indices_index| {
        const accessor = gltf_file.data.accessors.items[indices_index];
        std.debug.assert(accessor.type == .scalar);

        switch (accessor.component_type) {
            .unsigned_byte => {
                var it = accessor.iterator(u8, gltf_file, gltf_file.glb_binary.?);
                try indices.ensureTotalCapacity(indices.items.len + it.total_count);
                while (it.next()) |indices_slice| {
                    for (indices_slice) |indexes| {
                        indices.appendAssumeCapacity(@intCast(indexes));
                    }
                }
            },
            .unsigned_short => {
                var it = accessor.iterator(u16, gltf_file, gltf_file.glb_binary.?);
                try indices.ensureTotalCapacity(indices.items.len + it.total_count);
                while (it.next()) |indices_slice| {
                    for (indices_slice) |indexes| {
                        indices.appendAssumeCapacity(@intCast(indexes));
                    }
                }
            },
            .unsigned_integer => {
                var it = accessor.iterator(u32, gltf_file, gltf_file.glb_binary.?);
                try indices.ensureTotalCapacity(indices.items.len + it.total_count);
                while (it.next()) |indices_slice| {
                    indices.appendUnalignedSliceAssumeCapacity(indices_slice);
                }
            },
            else => unreachable,
        }
    }

    var found_tangents = false;

    for (primitive.attributes.items) |attribute| {
        switch (attribute) {
            .position => |index| {
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec3);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                try positions.ensureTotalCapacity(positions.items.len + it.total_count);
                while (it.next()) |position_slice| {
                    positions.appendAssumeCapacity(.{ position_slice[0], position_slice[1], position_slice[2] });
                }
            },
            .normal => |index| {
                if (normals) |n| {
                    const accessor = gltf_file.data.accessors.items[index];
                    std.debug.assert(accessor.type == .vec3);
                    std.debug.assert(accessor.component_type == .float);
                    var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                    try n.ensureTotalCapacity(n.items.len + it.total_count);
                    while (it.next()) |normal_slice| {
                        n.appendAssumeCapacity(.{ normal_slice[0], normal_slice[1], normal_slice[2] });
                    }
                }
            },
            .tangent => |index| {
                if (tangents) |t| {
                    const accessor = gltf_file.data.accessors.items[index];
                    std.debug.assert(accessor.type == .vec4);
                    std.debug.assert(accessor.component_type == .float);
                    var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                    try t.ensureTotalCapacity(t.items.len + it.total_count);
                    while (it.next()) |normal_slice| {
                        t.appendAssumeCapacity(.{ normal_slice[0], normal_slice[1], normal_slice[2], normal_slice[3] });
                    }
                    found_tangents = true;
                }
            },
            .texcoord => |index| {
                if (texcoords0) |tc| {
                    const accessor = gltf_file.data.accessors.items[index];
                    std.debug.assert(accessor.type == .vec2);
                    std.debug.assert(accessor.component_type == .float);
                    var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                    try tc.ensureTotalCapacity(tc.items.len + it.total_count);
                    while (it.next()) |uv_slice| {
                        tc.appendAssumeCapacity(.{ uv_slice[0], uv_slice[1] });
                    }
                }
            },
            else => {},
        }
    }

    // Create tangents if there are none
    if (tangents) |t| {
        if (!found_tangents) {
            const missing = positions.items.len - t.items.len;
            try t.appendNTimes(.{0.0} ** 4, missing);
        }
    }

    return;
}
