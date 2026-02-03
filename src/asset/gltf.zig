const std = @import("std");

const zgltf = @import("zgltf").Gltf;
const zm = @import("zmath");

const Camera = @import("../rendering/camera.zig").Camera;
const Transform = @import("../transform.zig");
const AssetHandle = @import("registry.zig").Handle;
const Material = @import("material.zig");
const Mesh = @import("mesh.zig");
const Scene = @import("scene.zig");
const stbi = @import("stbi.zig");
const Texture = @import("texture.zig");
const meshopt = @import("meshoptimizer.zig");

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

    const file_buffer: []align(4) const u8 = try file_dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, .@"16", null);
    try gltf_file.parse(file_buffer);

    var bin_buffer: ?[]align(4) u8 = null;
    if (gltf_file.glb_binary == null) {
        const bin_path = try replaceExt(allocator, file_path, ".bin");
        defer allocator.free(bin_path);

        bin_buffer = try file_dir.readFileAllocOptions(allocator, bin_path, std.math.maxInt(usize), null, .@"16", null);
        gltf_file.glb_binary = bin_buffer.?;
    } else {
        bin_buffer = try allocator.alignedAlloc(u8, .@"16", gltf_file.glb_binary.?.len);
        @memcpy(bin_buffer.?, gltf_file.glb_binary.?);
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
    if (self.bin_buffer) |buffer| {
        self.allocator.free(buffer);
        self.gltf_file.glb_binary = null;
    }

    self.parent_dir.close();
    self.gltf_file.deinit();
    self.asset_info.deinit();

    self.allocator.free(self.file_buffer);
}

pub fn getMeshCount(self: Self) usize {
    return self.gltf_file.data.meshes.len;
}

pub fn getTextureCount(self: Self) usize {
    return self.gltf_file.data.images.len;
}

pub fn getMaterialCount(self: Self) usize {
    return self.gltf_file.data.materials.len;
}

pub fn loadMesh(self: Self, allocator: std.mem.Allocator, gltf_index: usize) !struct { output_path: []const u8, value: Mesh } {
    if (gltf_index >= self.gltf_file.data.meshes.len) {
        return error.indexOutOfRange;
    }
    const gltf_mesh = self.gltf_file.data.meshes[gltf_index];

    const primitives = try allocator.alloc(meshopt.Primitive, gltf_mesh.primitives.len);
    defer allocator.free(primitives);

    var vertices: std.ArrayList(Mesh.Vertex) = .empty;
    defer vertices.deinit(allocator);

    var indices: std.ArrayList(Mesh.Index) = .empty;
    defer indices.deinit(allocator);

    for (gltf_mesh.primitives, 0..) |primitive, i| {
        primitives[i] = try loadGltfPrimitive(allocator, &self.gltf_file, &primitive, &vertices, &indices);
    }

    return .{
        .output_path = self.asset_info.meshes[gltf_index].path,
        .value = try meshopt.buildMesh(allocator, self.asset_info.meshes[gltf_index].name, vertices.items, indices.items, primitives, .{}),
    };
}

pub fn loadTexture(self: Self, allocator: std.mem.Allocator, gltf_index: usize) !struct { output_path: []const u8, value: Texture } {
    if (gltf_index >= self.gltf_file.data.images.len) {
        return error.indexOutOfRange;
    }
    const gltf_image = self.gltf_file.data.images[gltf_index];

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
    if (gltf_index >= self.gltf_file.data.materials.len) {
        return error.indexOutOfRange;
    }
    const gltf_material = self.gltf_file.data.materials[gltf_index];

    const alpha_mode: Material.AlphaMode = switch (gltf_material.alpha_mode) {
        .@"opaque" => .@"opaque",
        .mask => .mask,
        .blend => .blend,
    };

    var base_color_texture: ?AssetHandle = null;
    if (gltf_material.metallic_roughness.base_color_texture) |texture| {
        if (self.gltf_file.data.textures[texture.index].source) |texture_index| {
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
    if (gltf_index >= self.gltf_file.data.scenes.len) {
        return error.indexOutOfRange;
    }
    const gltf_scene = self.gltf_file.data.scenes[gltf_index];

    var name: []const u8 = &.{};
    if (gltf_scene.name) |gltf_name| {
        name = try allocator.dupe(u8, gltf_name);
    } else {
        name = try std.fmt.allocPrint(allocator, "scene_{}", .{gltf_index});
    }
    errdefer allocator.free(name);

    var nodes: std.ArrayList(Scene.Node) = .{};
    defer nodes.deinit(allocator);

    var root_nodes: []usize = &.{};
    if (gltf_scene.nodes) |gltf_root_nodes| {
        root_nodes = try allocator.alloc(usize, gltf_root_nodes.len);
        errdefer allocator.free(root_nodes);
        for (gltf_root_nodes, 0..) |child_index, list_index| {
            root_nodes[list_index] = try self.loadNode(allocator, child_index, &nodes);
        }
    }

    return .{
        .name = name,
        .root_nodes = root_nodes,
        .nodes = try nodes.toOwnedSlice(allocator),
    };
}

fn loadNode(self: Self, allocator: std.mem.Allocator, gltf_index: usize, nodes: *std.ArrayList(Scene.Node)) !usize {
    if (gltf_index >= self.gltf_file.data.nodes.len) {
        return error.indexOutOfRange;
    }
    const gltf_node = self.gltf_file.data.nodes[gltf_index];

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
        const gltf_mesh = self.gltf_file.data.meshes[mesh_index];
        var materials = try allocator.alloc(AssetHandle, gltf_mesh.primitives.len);
        errdefer allocator.free(materials);

        for (gltf_mesh.primitives, 0..) |prim, i| {
            materials[i] = self.asset_info.materials[prim.material.?].handle;
        }

        mesh = .{
            .mesh = self.asset_info.meshes[mesh_index].handle,
            .materials = materials,
        };
    }

    var camera: ?Camera = null;
    if (gltf_node.camera) |camera_index| {
        const gltf_camera = self.gltf_file.data.cameras[camera_index];

        camera = switch (gltf_camera.type) {
            .perspective => |perspective| .{ .perspective = .{
                .fov = .{ .y = std.math.radiansToDegrees(perspective.yfov) },
                .near = perspective.znear,
                .far = perspective.zfar,
            } },
            .orthographic => |orthographic| .{ .orthographic = .{
                .size = .{ .width = orthographic.xmag },
                .near = orthographic.znear,
                .far = orthographic.zfar,
            } },
        };
    }

    const parent: ?usize = gltf_node.parent;

    const children = try allocator.alloc(usize, gltf_node.children.len);
    errdefer allocator.free(children);
    for (gltf_node.children, 0..) |child_index, list_index| {
        children[list_index] = try self.loadNode(allocator, child_index, nodes);
    }

    const node_index = nodes.items.len;
    try nodes.append(allocator, .{
        .name = name,
        .local_transform = transform,
        .parent = parent,
        .children = children,
        .mesh = mesh,
        .camera = camera,
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
                .handle = .fromRepoPath(repo, path),
            };
        }

        fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.path);
        }
    };
}

const AssetHandles = struct {
    const MeshAssetInfo = AssetInfo(AssetHandle, "/meshes/", ".asset");
    const ImageAssetInfo = AssetInfo(AssetHandle, "/textures/", ".asset");
    const MaterialAssetInfo = AssetInfo(AssetHandle, "/materials/", ".asset");

    allocator: std.mem.Allocator,

    meshes: []MeshAssetInfo,
    images: []ImageAssetInfo,
    materials: []MaterialAssetInfo,

    fn init(allocator: std.mem.Allocator, repo: []const u8, output_path: []const u8, gltf: *zgltf.Data) !@This() {
        var meshes = try allocator.alloc(MeshAssetInfo, gltf.meshes.len);
        errdefer allocator.free(meshes);
        for (gltf.meshes, 0..) |mesh, i| {
            var mesh_name: []const u8 = &.{};
            if (mesh.name) |name| {
                mesh_name = try allocator.dupe(u8, name);
            } else {
                mesh_name = try std.fmt.allocPrint(allocator, "mesh_{}", .{i});
            }
            meshes[i] = try MeshAssetInfo.init(allocator, repo, output_path, mesh_name);
        }

        var images = try allocator.alloc(ImageAssetInfo, gltf.images.len);
        errdefer allocator.free(images);
        for (gltf.images, 0..) |image, i| {
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

        var materials = try allocator.alloc(MaterialAssetInfo, gltf.materials.len);
        errdefer allocator.free(materials);
        for (gltf.materials, 0..) |material, i| {
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

fn loadGltfPrimitive(
    allocator: std.mem.Allocator,
    gltf_file: *const zgltf,
    gltf_primitive: *const zgltf.Primitive,
    output_vertices: *std.ArrayList(Mesh.Vertex),
    output_indices: *std.ArrayList(Mesh.Index),
) !meshopt.Primitive {
    var indices: []u32 = &.{};
    defer allocator.free(indices);

    if (gltf_primitive.indices) |indices_index| {
        const accessor = gltf_file.data.accessors[indices_index];
        std.debug.assert(accessor.type == .scalar);

        switch (accessor.component_type) {
            .unsigned_byte => {
                const temp_indices = try gltf_file.getDataFromBufferView(u8, allocator, accessor, gltf_file.glb_binary.?);
                defer allocator.free(temp_indices);
                indices = try allocator.alloc(u32, temp_indices.len);
                for (indices, temp_indices) |*index, temp_index| {
                    index.* = @intCast(temp_index);
                }
            },
            .unsigned_short => {
                const temp_indices = try gltf_file.getDataFromBufferView(u16, allocator, accessor, gltf_file.glb_binary.?);
                defer allocator.free(temp_indices);
                indices = try allocator.alloc(u32, temp_indices.len);
                for (indices, temp_indices) |*index, temp_index| {
                    index.* = @intCast(temp_index);
                }
            },
            .unsigned_integer => {
                indices = try gltf_file.getDataFromBufferView(u32, allocator, accessor, gltf_file.glb_binary.?);
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

    const UV_ARRAY = [][2]f32;
    var uv_array_count: usize = 0;
    var uv_arrays: [8]UV_ARRAY = undefined;
    defer for (uv_arrays[0..uv_array_count]) |uv_array| {
        allocator.free(uv_array);
    };

    for (gltf_primitive.attributes) |attribute| {
        switch (attribute) {
            .position => |index| {
                std.debug.assert(positions.len == 0);
                const accessor = gltf_file.data.accessors[index];
                std.debug.assert(accessor.type == .vec3);
                std.debug.assert(accessor.component_type == .float);

                positions = try loadAttribueFloatArray(3, allocator, gltf_file, accessor);
            },
            .normal => |index| {
                std.debug.assert(normals.len == 0);
                const accessor = gltf_file.data.accessors[index];
                std.debug.assert(accessor.type == .vec3);
                std.debug.assert(accessor.component_type == .float);

                normals = try loadAttribueFloatArray(3, allocator, gltf_file, accessor);
            },
            .tangent => |index| {
                std.debug.assert(tangents.len == 0);
                const accessor = gltf_file.data.accessors[index];
                std.debug.assert(accessor.type == .vec4);
                std.debug.assert(accessor.component_type == .float);

                tangents = try loadAttribueFloatArray(4, allocator, gltf_file, accessor);
            },
            .texcoord => |index| {
                if (uv_array_count >= uv_arrays.len) {
                    continue;
                }

                const accessor = gltf_file.data.accessors[index];
                std.debug.assert(accessor.type == .vec2);
                std.debug.assert(accessor.component_type == .float);

                uv_arrays[uv_array_count] = try loadAttribueFloatArray(2, allocator, gltf_file, accessor);
                uv_array_count += 1;
            },
            else => {},
        }
    }

    const vertices = try allocator.alloc(Mesh.Vertex, positions.len);
    defer allocator.free(vertices);

    for (vertices, positions, normals, 0..) |*vertex, position, normal, i| {
        vertex.position = position;
        vertex.normal = normal;

        if (tangents.len != 0) {
            vertex.tangent = tangents[i];
        } else {
            vertex.tangent = .{ 0, 0, 0, 1 }; //TODO: gen tangets if non are provided

        }
    }

    if (uv_array_count >= 1) {
        const uv0s: UV_ARRAY = uv_arrays[0];
        for (vertices, uv0s) |*vertex, uv| {
            vertex.uv0 = uv;
        }
    }

    if (uv_array_count >= 2) {
        const uv1s: UV_ARRAY = uv_arrays[1];
        for (vertices, uv1s) |*vertex, uv| {
            vertex.uv1 = uv;
        }
    }

    const vertex_offset: u32 = @intCast(output_vertices.items.len);
    const vertex_count: u32 = @intCast(vertices.len);

    const index_offset: u32 = @intCast(output_indices.items.len);
    const index_count: u32 = @intCast(indices.len);

    try output_vertices.appendSlice(allocator, vertices);
    try output_indices.appendSlice(allocator, indices);

    return .{
        .vertex_offset = vertex_offset,
        .vertex_count = vertex_count,

        .index_offset = index_offset,
        .index_count = index_count,
    };
}

fn loadAttribueFloatArray(
    comptime SliceCount: comptime_int,
    allocator: std.mem.Allocator,
    gltf_file: *const zgltf,
    accessor: zgltf.Accessor,
) ![][SliceCount]f32 {
    const float_array = try gltf_file.getDataFromBufferView(f32, allocator, accessor, gltf_file.glb_binary.?);
    defer allocator.free(float_array);

    std.debug.assert(accessor.count == (float_array.len / SliceCount));

    const attributes = try allocator.alloc([SliceCount]f32, accessor.count);
    for (attributes, 0..) |*value, i| {
        const float_i: usize = i * SliceCount;

        //Really hope that the compiler loop unrolls this cause its comptime known
        for (0..SliceCount) |sub_i| {
            value.*[sub_i] = float_array[float_i + sub_i];
        }
    }
    return attributes;
}
