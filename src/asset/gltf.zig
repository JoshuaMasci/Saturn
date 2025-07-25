const std = @import("std");

const zm = @import("zmath");
const Transform = @import("../transform.zig");

const Mesh = @import("mesh.zig");
const Texture2D = @import("texture.zig");
const Material = @import("material.zig");
const Scene = @import("scene.zig");

const stbi = @import("stbi.zig");
const zgltf = @import("zgltf");

//TODO: move to a string utils
fn replaceExt(allocator: std.mem.Allocator, path: []const u8, new_ext: []const u8) ![]const u8 {
    const current_ext = std.fs.path.extension(path);
    if (current_ext.len == 0) {
        unreachable;
    } else {
        const base_path_len = path.len - current_ext.len;
        const new_len = base_path_len + new_ext.len;
        var new_path = try allocator.alloc(u8, new_len);
        std.mem.copyForwards(u8, new_path, path[0..base_path_len]);
        std.mem.copyForwards(u8, new_path[base_path_len..], new_ext);
        return new_path;
    }
}

const Self = @This();

allocator: std.mem.Allocator,

file_buffer: []align(4) const u8,
bin_buffer: ?[]align(4) const u8,

gltf_file: zgltf,
parent_dir: std.fs.Dir,
asset_info: AssetHandles,

pub fn init(
    allocator: std.mem.Allocator,
    file_dir: std.fs.Dir,
    file_path: []const u8,
    repo_name: []const u8,
    output_path: []const u8,
) !Self {
    var gltf_file = zgltf.init(allocator);

    const parent_path = std.fs.path.dirname(file_path) orelse ".";
    const parent_dir = try file_dir.openDir(parent_path, .{});

    const file_buffer = try file_dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
    try gltf_file.parse(file_buffer);

    var bin_buffer: ?[]align(4) const u8 = null;
    if (gltf_file.glb_binary == null) {
        const bin_path = try replaceExt(allocator, file_path, ".bin");
        defer allocator.free(bin_path);

        bin_buffer = try file_dir.readFileAllocOptions(allocator, bin_path, std.math.maxInt(usize), null, 4, null);
        gltf_file.glb_binary = bin_buffer.?;
    }

    const asset_info = try AssetHandles.init(allocator, repo_name, output_path, &gltf_file.data);

    return .{
        .allocator = allocator,
        .file_buffer = file_buffer,
        .bin_buffer = bin_buffer,

        .gltf_file = gltf_file,
        .parent_dir = parent_dir,
        .asset_info = asset_info,
    };
}

pub fn deinit(self: *Self) void {
    self.parent_dir.close();
    self.gltf_file.deinit();
    self.asset_info.deinit();

    if (self.bin_buffer) |buffer| {
        self.allocator.free(buffer);
        self.gltf_file.glb_binary = null;
    }
    self.allocator.free(self.file_buffer);
}

pub fn getMeshCount(self: Self) usize {
    return self.gltf_file.data.meshes.items.len;
}

pub fn getTextureCount(self: Self) usize {
    return self.gltf_file.data.images.items.len;
}

pub fn getMaterialCount(self: Self) usize {
    return self.gltf_file.data.materials.items.len;
}

pub fn loadMesh(self: Self, allocator: std.mem.Allocator, gltf_index: usize) !struct { output_path: []const u8, value: Mesh } {
    if (gltf_index >= self.gltf_file.data.meshes.items.len) {
        return error.indexOutOfRange;
    }
    const gltf_mesh = self.gltf_file.data.meshes.items[gltf_index];

    const mesh_name: []const u8 = try allocator.dupe(u8, self.asset_info.meshes[gltf_index].name);

    const primitives = try allocator.alloc(Mesh.Primitive, gltf_mesh.primitives.items.len);
    errdefer allocator.free(primitives);

    for (gltf_mesh.primitives.items, 0..) |primitive, i| {
        primitives[i] = try loadGltfPrimitive(allocator, &self.gltf_file, &primitive);
    }

    var mesh: Mesh = .{
        .name = mesh_name,
        .sphere_pos_radius = undefined,
        .primitives = primitives,
    };
    mesh.calcBoundingSphere();

    return .{
        .output_path = self.asset_info.meshes[gltf_index].path,
        .value = mesh,
    };
}

pub fn loadTexture(self: Self, allocator: std.mem.Allocator, gltf_index: usize) !struct { output_path: []const u8, value: Texture2D } {
    if (gltf_index >= self.gltf_file.data.images.items.len) {
        return error.indexOutOfRange;
    }
    const gltf_image = self.gltf_file.data.images.items[gltf_index];

    if (gltf_image.data) |data| {
        return .{
            .output_path = self.asset_info.images[gltf_index].path,
            .value = try stbi.load(allocator, self.asset_info.images[gltf_index].name, data),
        };
    }

    if (gltf_image.uri) |uri| {
        return .{
            .output_path = self.asset_info.images[gltf_index].path,
            .value = try stbi.loadFromFile(allocator, self.parent_dir, self.asset_info.images[gltf_index].name, uri),
        };
    }

    return error.NoImageSource;
}

pub fn loadMaterial(self: Self, allocator: std.mem.Allocator, gltf_index: usize) !struct { output_path: []const u8, value: Material } {
    if (gltf_index >= self.gltf_file.data.materials.items.len) {
        return error.indexOutOfRange;
    }
    const gltf_material = self.gltf_file.data.materials.items[gltf_index];

    const alpha_mode: Material.AlphaMode = switch (gltf_material.alpha_mode) {
        .@"opaque" => .alpha_opaque,
        .mask => .alpha_mask,
        .blend => .alpha_blend,
    };

    var base_color_texture: ?Texture2D.Registry.Handle = null;
    if (gltf_material.metallic_roughness.base_color_texture) |texture| {
        if (self.gltf_file.data.textures.items[texture.index].source) |texture_index| {
            base_color_texture = self.asset_info.images[texture_index].handle;
        }
    }

    const material: Material = .{
        .name = try allocator.dupe(u8, self.asset_info.materials[gltf_index].name),

        .alpha_mode = alpha_mode,
        .alpha_cutoff = gltf_material.alpha_cutoff,

        .base_color_factor = gltf_material.metallic_roughness.base_color_factor,
        .base_color_texture = base_color_texture,

        .metallic_roughness_factor = .{ gltf_material.metallic_roughness.metallic_factor, gltf_material.metallic_roughness.roughness_factor },
        .emissive_factor = gltf_material.emissive_factor,
    };

    return .{
        .output_path = self.asset_info.materials[gltf_index].path,
        .value = material,
    };
}

pub fn loadScene(self: Self, allocator: std.mem.Allocator, gltf_index: usize) !Scene {
    if (gltf_index >= self.gltf_file.data.scenes.items.len) {
        return error.indexOutOfRange;
    }
    const gltf_scene = self.gltf_file.data.scenes.items[gltf_index];

    var name: []const u8 = &.{};
    if (gltf_scene.name) |gltf_name| {
        name = try allocator.dupe(u8, gltf_name);
    } else {
        name = try std.fmt.allocPrint(allocator, "scene_{}", .{gltf_index});
    }
    errdefer allocator.free(name);

    var nodes = std.ArrayList(Scene.Node).init(allocator);
    defer nodes.deinit();

    var root_nodes: []usize = &.{};
    if (gltf_scene.nodes) |gltf_root_nodes| {
        root_nodes = try allocator.alloc(usize, gltf_root_nodes.items.len);
        errdefer allocator.free(root_nodes);
        for (gltf_root_nodes.items, 0..) |child_index, list_index| {
            root_nodes[list_index] = try self.loadNode(allocator, child_index, &nodes);
        }
    }

    return .{
        .name = name,
        .root_nodes = root_nodes,
        .nodes = try nodes.toOwnedSlice(),
    };
}

fn loadNode(self: Self, allocator: std.mem.Allocator, gltf_index: usize, nodes: *std.ArrayList(Scene.Node)) !usize {
    if (gltf_index >= self.gltf_file.data.nodes.items.len) {
        return error.indexOutOfRange;
    }
    const gltf_node = self.gltf_file.data.nodes.items[gltf_index];

    var name: []const u8 = &.{};
    if (gltf_node.name) |gltf_name| {
        name = try allocator.dupe(u8, gltf_name);
    } else {
        name = try std.fmt.allocPrint(allocator, "node_{}", .{gltf_index});
    }
    errdefer allocator.free(name);

    const transform: Transform = .{
        .position = zm.loadArr3(gltf_node.translation),
        .rotation = zm.loadArr4(gltf_node.rotation),
        .scale = zm.loadArr3(gltf_node.scale),
    };

    var mesh: ?Scene.Mesh = null;
    if (gltf_node.mesh) |mesh_index| {
        const gltf_mesh = self.gltf_file.data.meshes.items[mesh_index];
        var materials = try allocator.alloc(Material.Registry.Handle, gltf_mesh.primitives.items.len);
        errdefer allocator.free(materials);

        for (gltf_mesh.primitives.items, 0..) |prim, i| {
            materials[i] = self.asset_info.materials[prim.material.?].handle;
        }

        mesh = .{
            .mesh = self.asset_info.meshes[mesh_index].handle,
            .materials = materials,
        };
    }

    const children = try allocator.alloc(usize, gltf_node.children.items.len);
    errdefer allocator.free(children);
    for (gltf_node.children.items, 0..) |child_index, list_index| {
        children[list_index] = try self.loadNode(allocator, child_index, nodes);
    }

    const node_index = nodes.items.len;
    try nodes.append(.{
        .name = name,
        .local_transform = transform,
        .mesh = mesh,
        .children = children,
    });
    return node_index;
}

fn AssetInfo(comptime Handle: type, comptime sub_path: []const u8, comptime file_ext: []const u8) type {
    return struct {
        name: []const u8,
        path: []const u8,
        handle: Handle,

        fn init(
            allocator: std.mem.Allocator,
            repo: []const u8,
            dir_path: []const u8,
            asset_name: []const u8,
        ) !@This() {
            const path = try std.fmt.allocPrint(allocator, "{s}{s}{s}{s}", .{ dir_path, sub_path, asset_name, file_ext });
            return .{
                .name = asset_name,
                .path = path,
                .handle = .fromRepoPathSeprate(repo, path),
            };
        }

        fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.path);
        }
    };
}

const AssetHandles = struct {
    const MeshAssetInfo = AssetInfo(Mesh.Registry.Handle, "/meshes/", ".mesh");
    const ImageAssetInfo = AssetInfo(Texture2D.Registry.Handle, "/textures/", ".tex");
    const MaterialAssetInfo = AssetInfo(Material.Registry.Handle, "/materials/", ".mat");

    allocator: std.mem.Allocator,

    meshes: []MeshAssetInfo,
    images: []ImageAssetInfo,
    materials: []MaterialAssetInfo,

    fn init(allocator: std.mem.Allocator, repo: []const u8, output_path: []const u8, gltf: *zgltf.Data) !@This() {
        var meshes = try allocator.alloc(MeshAssetInfo, gltf.meshes.items.len);
        errdefer allocator.free(meshes);
        for (gltf.meshes.items, 0..) |mesh, i| {
            var mesh_name: []const u8 = &.{};
            if (mesh.name) |name| {
                mesh_name = try allocator.dupe(u8, name);
            } else {
                mesh_name = try std.fmt.allocPrint(allocator, "mesh_{}", .{i});
            }
            meshes[i] = try MeshAssetInfo.init(allocator, repo, output_path, mesh_name);
        }

        var images = try allocator.alloc(ImageAssetInfo, gltf.images.items.len);
        errdefer allocator.free(images);
        for (gltf.images.items, 0..) |image, i| {
            var image_name: []const u8 = &.{};
            if (image.uri) |uri| {
                image_name = try allocator.dupe(u8, std.fs.path.stem(uri));
            } else if (image.name) |name| {
                image_name = try allocator.dupe(u8, name);
            } else {
                image_name = try std.fmt.allocPrint(allocator, "image_{}", .{i});
            }
            images[i] = try ImageAssetInfo.init(allocator, repo, output_path, image_name);
        }

        var materials = try allocator.alloc(MaterialAssetInfo, gltf.materials.items.len);
        errdefer allocator.free(materials);
        for (gltf.materials.items, 0..) |material, i| {
            var material_name: []const u8 = &.{};
            if (material.name) |name| {
                material_name = try allocator.dupe(u8, name);
            } else {
                material_name = try std.fmt.allocPrint(allocator, "material_{}", .{i});
            }
            materials[i] = try MaterialAssetInfo.init(allocator, repo, output_path, material_name);
        }

        return .{
            .allocator = allocator,
            .meshes = meshes,
            .images = images,
            .materials = materials,
        };
    }

    fn deinit(self: @This()) void {
        for (self.meshes) |mesh| {
            mesh.deinit(self.allocator);
        }
        self.allocator.free(self.meshes);

        for (self.images) |image| {
            image.deinit(self.allocator);
        }
        self.allocator.free(self.images);

        for (self.materials) |material| {
            material.deinit(self.allocator);
        }
        self.allocator.free(self.materials);
    }
};

fn loadGltfPrimitive(allocator: std.mem.Allocator, gltf_file: *const zgltf, gltf_primitive: *const zgltf.Primitive) !Mesh.Primitive {
    var indices: []u32 = &.{};
    errdefer allocator.free(indices);

    if (gltf_primitive.indices) |indices_index| {
        const accessor = gltf_file.data.accessors.items[indices_index];
        std.debug.assert(accessor.type == .scalar);

        switch (accessor.component_type) {
            .unsigned_byte => {
                var it = accessor.iterator(u8, gltf_file, gltf_file.glb_binary.?);
                indices = try allocator.alloc(u32, it.total_count);
                var i: usize = 0;
                while (it.next()) |indices_slice| {
                    for (indices_slice) |indexes| {
                        indices[i] = @intCast(indexes);
                        i += 1;
                    }
                }
            },
            .unsigned_short => {
                var it = accessor.iterator(u16, gltf_file, gltf_file.glb_binary.?);
                indices = try allocator.alloc(u32, it.total_count);
                var i: usize = 0;
                while (it.next()) |indices_slice| {
                    for (indices_slice) |indexes| {
                        indices[i] = @intCast(indexes);
                        i += 1;
                    }
                }
            },
            .unsigned_integer => {
                var it = accessor.iterator(u32, gltf_file, gltf_file.glb_binary.?);
                indices = try allocator.alloc(u32, it.total_count);
                var i: usize = 0;
                while (it.next()) |indices_slice| {
                    for (indices_slice) |indexes| {
                        indices[i] = @intCast(indexes);
                        i += 1;
                    }
                }
            },
            else => |unknown_type| std.log.err("Unknown Index type: {}", .{unknown_type}),
        }
    }

    var positions: [][3]f32 = &.{};
    defer allocator.free(positions);

    var normals: [][3]f32 = &.{};
    defer allocator.free(normals);

    var tangents: [][4]f32 = &.{};
    defer allocator.free(tangents);

    var uv_arrays = try std.BoundedArray([][2]f32, 8).init(0);
    defer for (uv_arrays.slice()) |uv_array| {
        allocator.free(uv_array);
    };

    for (gltf_primitive.attributes.items) |attribute| {
        switch (attribute) {
            .position => |index| {
                std.debug.assert(positions.len == 0);
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec3);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);

                positions = try allocator.alloc([3]f32, it.total_count);
                var i: usize = 0;
                while (it.next()) |position_slice| {
                    positions[i] = .{ position_slice[0], position_slice[1], position_slice[2] };
                    i += 1;
                }
            },
            .normal => |index| {
                std.debug.assert(normals.len == 0);
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec3);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);

                normals = try allocator.alloc([3]f32, it.total_count);
                var i: usize = 0;
                while (it.next()) |normal_slice| {
                    normals[i] = .{ normal_slice[0], normal_slice[1], normal_slice[2] };
                    i += 1;
                }
            },
            .tangent => |index| {
                std.debug.assert(tangents.len == 0);
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec4);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);

                tangents = try allocator.alloc([4]f32, it.total_count);
                var i: usize = 0;
                while (it.next()) |tangent_slice| {
                    tangents[i] = .{ tangent_slice[0], tangent_slice[1], tangent_slice[2], tangent_slice[3] };
                    i += 1;
                }
            },
            .texcoord => |index| {
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec2);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);

                var uvs = try allocator.alloc([2]f32, it.total_count);
                var i: usize = 0;
                while (it.next()) |uv_slice| {
                    uvs[i] = .{ uv_slice[0], uv_slice[1] };
                    i += 1;
                }
                uv_arrays.appendAssumeCapacity(uvs);
            },
            else => {},
        }
    }

    const vertices = try allocator.alloc(Mesh.Vertex, positions.len);
    errdefer allocator.free(vertices);

    for (vertices, positions) |*vertex, position| {
        vertex.position = position;
    }

    for (vertices, normals) |*vertex, normal| {
        vertex.normal = normal;
    }

    if (tangents.len != 0) {
        for (vertices, tangents) |*vertex, tangent| {
            vertex.tangent = tangent;
        }
    } else {
        //TODO: gen tangets if non are provided
        for (vertices) |*vertex| {
            vertex.tangent = .{ 0, 0, 0, 1 };
        }
    }

    if (uv_arrays.len >= 1) {
        const uv0s = uv_arrays.get(0);
        for (vertices, uv0s) |*vertex, uv| {
            vertex.uv0 = uv;
        }
    }

    if (uv_arrays.len >= 2) {
        const uv1s = uv_arrays.get(0);
        for (vertices, uv1s) |*vertex, uv| {
            vertex.uv1 = uv;
        }
    }

    return .{
        .sphere_pos_radius = undefined,
        .vertices = vertices,
        .indices = indices,
    };
}
