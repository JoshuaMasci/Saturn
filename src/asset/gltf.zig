//TODO: rewrite for new asset system?

const std = @import("std");
const za = @import("zalgebra");

const zgltf = @import("zgltf");

const zstbi = @import("zstbi");

const Transform = @import("transform.zig");
const object_pool = @import("object_pool.zig");

pub const File = struct {
    const Self = @This();

    images: std.ArrayList(?zstbi.Image),
    samplers: std.ArrayList(Sampler),
    textures: std.ArrayList(Texture),
    materials: std.ArrayList(Material),
    meshes: std.ArrayList(?Mesh),
    scenes: std.ArrayList(?Scene),

    default_scene: ?usize = null,

    pub fn deinit(self: *Self) void {
        for (self.images.items) |*image_opt| {
            if (image_opt.*) |*image| {
                image.deinit();
            }
        }
        self.images.deinit();

        self.samplers.deinit();
        self.textures.deinit();

        for (self.materials.items) |*material| {
            material.deinit();
        }
        self.materials.deinit();

        for (self.meshes.items) |*mesh_opt| {
            if (mesh_opt.*) |*mesh| {
                mesh.deinit();
            }
        }
        self.meshes.deinit();

        for (self.scenes.items) |*scene_opt| {
            if (scene_opt.*) |*scene| {
                scene.deinit();
            }
        }
        self.scenes.deinit();
    }
};

pub const MinFiltering = enum {
    linear,
    nearest,
    nearest_mipmap_nearest,
    linear_mipmap_nearest,
    nearest_mipmap_linear,
    linear_mipmap_linear,
};

pub const MagFiltering = enum {
    linear,
    nearest,
};

pub const AddressMode = enum {
    clamp_to_edge,
    mirrored_repeat,
    repeat,
};

pub const Sampler = struct {
    min: ?MinFiltering = null,
    mag: ?MagFiltering = null,
    address_mode_u: AddressMode = .repeat,
    address_mode_v: AddressMode = .repeat,
};

pub const Texture = struct {
    image_index: ?usize = null,
    sampler_index: ?usize = null,
};

const TextureInfo = struct {
    index: usize,
    texcoord: i32 = 0,
};

const ScaledTextureInfo = struct {
    index: usize,
    texcoord: i32 = 0,
    scale: f32 = 1,
};

pub const Material = struct {
    name: std.ArrayList(u8),

    base_color_texture: ?TextureInfo = null,
    base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

    metallic_roughness_texture: ?TextureInfo = null,
    metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

    emissive_texture: ?TextureInfo = null,
    emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

    normal_texture: ?ScaledTextureInfo = null,
    occlusion_texture: ?ScaledTextureInfo = null,

    pub fn deinit(self: *@This()) void {
        self.name.deinit();
    }
};

pub const Primitive = struct {
    default_material_index: ?usize = null,
    positions: ?std.ArrayList([3]f32) = null,
    normals: ?std.ArrayList([3]f32) = null,
    tangents: ?std.ArrayList([4]f32) = null,
    uv0s: ?std.ArrayList([2]f32) = null,
    indices: ?std.ArrayList(u32) = null,

    pub fn deinit(self: *@This()) void {
        if (self.positions) |positions| positions.deinit();
        if (self.normals) |normals| normals.deinit();
        if (self.tangents) |tangents| tangents.deinit();
        if (self.uv0s) |uv0s| uv0s.deinit();
        if (self.indices) |indices| indices.deinit();
    }
};

pub const Mesh = struct {
    name: std.ArrayList(u8),
    primitives: std.ArrayList(Primitive),

    pub fn deinit(self: *@This()) void {
        self.name.deinit();

        for (self.primitives.items) |*primitive| {
            primitive.deinit();
        }
        self.primitives.deinit();
    }
};

const NodePool = object_pool.ObjectPool(u16, Node);
pub const NodeHandle = NodePool.Handle;
const NodeHandleArrayList = std.ArrayList(NodeHandle);

pub const Node = struct {
    name: std.ArrayList(u8),
    transform: Transform = .{},
    mesh: ?usize = null,
    camera: ?void = null,
    light: ?void = null,
    children: NodeHandleArrayList,

    pub fn deinit(self: *@This()) void {
        self.name.deinit();
        self.children.deinit();
    }
};

pub const Scene = struct {
    const Self = @This();

    name: std.ArrayList(u8),
    pool: NodePool,
    root_nodes: NodeHandleArrayList,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .name = std.ArrayList(u8).init(allocator),
            .pool = NodePool.init(allocator),
            .root_nodes = NodeHandleArrayList.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.name.deinit();
        self.pool.deinit_with_entries();
        self.root_nodes.deinit();
    }
};

pub fn load_gltf_file(allocator: std.mem.Allocator, file_path: []const u8) !File {
    var gltf_file = zgltf.init(allocator);
    defer gltf_file.deinit();

    const parent_path = std.fs.path.dirname(file_path) orelse ".";

    const file_buffer = try std.fs.cwd().readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
    defer allocator.free(file_buffer);
    try gltf_file.parse(file_buffer);

    //TODO: load .bin if not .glb

    var images = try std.ArrayList(?zstbi.Image).initCapacity(allocator, gltf_file.data.images.items.len);
    for (gltf_file.data.images.items, 0..) |*glft_image, i| {
        const result: ?zstbi.Image = load_gltf_image(allocator, parent_path, glft_image) catch |err| val: {
            std.log.err("Failed to load {s} image {}: {}", .{ file_path, i, err });
            break :val null;
        };
        images.appendAssumeCapacity(result);
    }

    var samplers = try std.ArrayList(Sampler).initCapacity(allocator, gltf_file.data.samplers.items.len);
    for (gltf_file.data.samplers.items) |*sampler| {
        samplers.appendAssumeCapacity(load_gltf_sampler(sampler));
    }

    var textures = try std.ArrayList(Texture).initCapacity(allocator, gltf_file.data.textures.items.len);
    for (gltf_file.data.textures.items) |*texture| {
        textures.appendAssumeCapacity(load_gltf_texture(texture));
    }

    var materials = try std.ArrayList(Material).initCapacity(allocator, gltf_file.data.materials.items.len);
    for (gltf_file.data.materials.items) |*material| {
        materials.appendAssumeCapacity(try load_gltf_material(allocator, material));
    }

    var meshes = try std.ArrayList(?Mesh).initCapacity(allocator, gltf_file.data.meshes.items.len);
    for (gltf_file.data.meshes.items, 0..) |*glft_mesh, i| {
        const result: ?Mesh = load_gltf_mesh(allocator, &gltf_file, glft_mesh) catch |err| val: {
            std.log.err("Failed to load {s} mesh {}: {}", .{ file_path, i, err });
            break :val null;
        };
        meshes.appendAssumeCapacity(result);
    }

    var scenes = try std.ArrayList(?Scene).initCapacity(allocator, gltf_file.data.images.items.len);
    for (gltf_file.data.scenes.items, 0..) |*glft_scene, i| {
        const result: ?Scene = load_gltf_scene(allocator, &gltf_file.data, glft_scene) catch |err| val: {
            std.log.err("Failed to load {s} scene {}: {}", .{ file_path, i, err });
            break :val null;
        };
        scenes.appendAssumeCapacity(result);
    }

    return .{
        .images = images,
        .samplers = samplers,
        .textures = textures,
        .materials = materials,
        .meshes = meshes,
        .scenes = scenes,
        .default_scene = gltf_file.data.scene,
    };
}

fn load_gltf_image(allocator: std.mem.Allocator, parent_path: []const u8, gltf_image: *const zgltf.Image) !zstbi.Image {
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
        return try zstbi.Image.loadFromFile(full_path.items[0..(full_path.items.len - 1) :0], 0);
    }
    return error.NoImageSource;
}

fn load_gltf_sampler(gltf_sampler: *const zgltf.TextureSampler) Sampler {
    var sampler = Sampler{};

    if (gltf_sampler.min_filter) |min_filter| {
        sampler.min = switch (min_filter) {
            .nearest => .nearest,
            .linear => .linear,
            .nearest_mipmap_nearest => .nearest_mipmap_nearest,
            .linear_mipmap_nearest => .linear_mipmap_nearest,
            .nearest_mipmap_linear => .nearest_mipmap_linear,
            .linear_mipmap_linear => .linear_mipmap_linear,
        };
    }

    if (gltf_sampler.mag_filter) |mag_filter| {
        sampler.min = switch (mag_filter) {
            .nearest => .nearest,
            .linear => .linear,
        };
    }

    sampler.address_mode_u = switch (gltf_sampler.wrap_s) {
        .clamp_to_edge => .clamp_to_edge,
        .mirrored_repeat => .mirrored_repeat,
        .repeat => .repeat,
    };

    sampler.address_mode_u = switch (gltf_sampler.wrap_t) {
        .clamp_to_edge => .clamp_to_edge,
        .mirrored_repeat => .mirrored_repeat,
        .repeat => .repeat,
    };

    return sampler;
}

fn load_gltf_texture(gltf_texture: *const zgltf.Texture) Texture {
    return .{
        .image_index = gltf_texture.source,
        .sampler_index = gltf_texture.sampler,
    };
}

fn load_gltf_material(allocator: std.mem.Allocator, gltf_material: *const zgltf.Material) !Material {
    var name = try std.ArrayList(u8).initCapacity(allocator, gltf_material.name.len);
    name.appendSliceAssumeCapacity(gltf_material.name);

    var material: Material = .{ .name = name };

    material.base_color_factor = gltf_material.metallic_roughness.base_color_factor;
    if (gltf_material.metallic_roughness.base_color_texture) |texture| {
        material.base_color_texture = .{ .index = texture.index, .texcoord = texture.texcoord };
    }

    material.metallic_roughness_factor = .{ gltf_material.metallic_roughness.metallic_factor, gltf_material.metallic_roughness.roughness_factor };
    if (gltf_material.metallic_roughness.metallic_roughness_texture) |texture| {
        material.metallic_roughness_texture = .{ .index = texture.index, .texcoord = texture.texcoord };
    }

    if (gltf_material.normal_texture) |texture| {
        material.normal_texture = .{ .index = texture.index, .texcoord = texture.texcoord, .scale = texture.scale };
    }

    if (gltf_material.occlusion_texture) |texture| {
        material.occlusion_texture = .{ .index = texture.index, .texcoord = texture.texcoord, .scale = texture.strength };
    }

    return material;
}

fn load_gltf_mesh(allocator: std.mem.Allocator, gltf_file: *const zgltf, gltf_mesh: *const zgltf.Mesh) !Mesh {
    var name = try std.ArrayList(u8).initCapacity(allocator, gltf_mesh.name.len);
    name.appendSliceAssumeCapacity(gltf_mesh.name);

    var primitives = try std.ArrayList(Primitive).initCapacity(allocator, gltf_mesh.primitives.items.len);
    for (gltf_mesh.primitives.items) |*gltf_primitive| {
        primitives.appendAssumeCapacity(try load_gltf_primitive(allocator, gltf_file, gltf_primitive));
    }

    return .{
        .name = name,
        .primitives = primitives,
    };
}

fn load_gltf_primitive(allocator: std.mem.Allocator, gltf_file: *const zgltf, gltf_primitive: *const zgltf.Primitive) !Primitive {
    var primitive = Primitive{ .default_material_index = gltf_primitive.material };

    if (gltf_primitive.indices) |indices_index| {
        const accessor = gltf_file.data.accessors.items[indices_index];
        std.debug.assert(accessor.type == .scalar);

        var indices = std.ArrayList(u32).init(allocator);

        switch (accessor.component_type) {
            .unsigned_byte => {
                var it = accessor.iterator(u8, gltf_file, gltf_file.glb_binary.?);
                try indices.ensureTotalCapacity(it.total_count);
                while (it.next()) |indices_slice| {
                    for (indices_slice) |indexes| {
                        indices.appendAssumeCapacity(@intCast(indexes));
                    }
                }
            },
            .unsigned_short => {
                var it = accessor.iterator(u16, gltf_file, gltf_file.glb_binary.?);
                try indices.ensureTotalCapacity(it.total_count);
                while (it.next()) |indices_slice| {
                    for (indices_slice) |indexes| {
                        indices.appendAssumeCapacity(@intCast(indexes));
                    }
                }
            },
            .unsigned_integer => {
                var it = accessor.iterator(u32, gltf_file, gltf_file.glb_binary.?);
                try indices.ensureTotalCapacity(it.total_count);
                while (it.next()) |indices_slice| {
                    indices.appendUnalignedSliceAssumeCapacity(indices_slice);
                }
            },
            else => unreachable,
        }

        primitive.indices = indices;
    }

    for (gltf_primitive.attributes.items) |attribute| {
        switch (attribute) {
            .position => |index| {
                std.debug.assert(primitive.positions == null);
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec3);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                var positions = try std.ArrayList([3]f32).initCapacity(allocator, it.total_count);
                while (it.next()) |position_slice| {
                    positions.appendAssumeCapacity(.{ position_slice[0], position_slice[1], position_slice[2] });
                }
                primitive.positions = positions;
            },
            .normal => |index| {
                if (primitive.normals == null) {
                    const accessor = gltf_file.data.accessors.items[index];
                    std.debug.assert(accessor.type == .vec3);
                    std.debug.assert(accessor.component_type == .float);
                    var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                    var normals = try std.ArrayList([3]f32).initCapacity(allocator, it.total_count);
                    while (it.next()) |normal_slice| {
                        normals.appendAssumeCapacity(.{ normal_slice[0], normal_slice[1], normal_slice[2] });
                    }
                    primitive.normals = normals;
                }
            },
            .tangent => |index| {
                if (primitive.tangents == null) {
                    const accessor = gltf_file.data.accessors.items[index];
                    std.debug.assert(accessor.type == .vec4);
                    std.debug.assert(accessor.component_type == .float);
                    var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                    var tangents = try std.ArrayList([4]f32).initCapacity(allocator, it.total_count);
                    while (it.next()) |tangent_slice| {
                        tangents.appendAssumeCapacity(.{ tangent_slice[0], tangent_slice[1], tangent_slice[2], tangent_slice[3] });
                    }
                    primitive.tangents = tangents;
                }
            },
            .texcoord => |index| {
                if (primitive.uv0s == null) {
                    const accessor = gltf_file.data.accessors.items[index];
                    std.debug.assert(accessor.type == .vec2);
                    std.debug.assert(accessor.component_type == .float);
                    var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                    var uvs = try std.ArrayList([2]f32).initCapacity(allocator, it.total_count);
                    while (it.next()) |uv_slice| {
                        uvs.appendAssumeCapacity(.{ uv_slice[0], uv_slice[1] });
                    }
                    primitive.uv0s = uvs;
                }
            },
            else => {},
        }
    }

    return primitive;
}

pub fn load_gltf_scene(allocator: std.mem.Allocator, gltf_data: *const zgltf.Data, gltf_scene: *const zgltf.Scene) !Scene {
    var scene = Scene.init(allocator);
    try scene.name.appendSlice(gltf_scene.name);

    if (gltf_scene.nodes) |root_nodes| {
        for (root_nodes.items) |child_node_index| {
            try scene.root_nodes.append(try load_gltf_node(
                &scene,
                allocator,
                gltf_data,
                &gltf_data.nodes.items[child_node_index],
            ));
        }
    }

    return scene;
}

fn load_gltf_node(scene: *Scene, allocator: std.mem.Allocator, gltf_data: *const zgltf.Data, gltf_node: *const zgltf.Node) !NodeHandle {
    var node: Node = .{
        .name = std.ArrayList(u8).init(allocator),
        .children = try NodeHandleArrayList.initCapacity(allocator, gltf_node.children.items.len),
    };
    try node.name.appendSlice(gltf_node.name);

    node.transform.position = za.Vec3.fromArray(gltf_node.translation);
    node.transform.rotation = za.Quat.fromArray(gltf_node.rotation);
    node.transform.scale = za.Vec3.fromArray(gltf_node.scale);

    //TODO: if has_matrix decompose mat4 to transform
    // std.debug.assert(gltf_node.matrix == null);

    node.mesh = gltf_node.mesh;

    for (gltf_node.children.items) |child_node_index| {
        node.children.appendAssumeCapacity(try load_gltf_node(
            scene,
            allocator,
            gltf_data,
            &gltf_data.nodes.items[child_node_index],
        ));
    }

    return try scene.pool.insert(node);
}
