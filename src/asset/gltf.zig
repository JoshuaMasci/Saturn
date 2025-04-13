const std = @import("std");

const Texture2D = @import("texture_2d.zig");
const Mesh = @import("mesh.zig");
const stbi = @import("stbi.zig");

const zgltf = @import("zgltf");

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

pub const File = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    scenes: []?Scene,
    meshes: []?Mesh,
    textures: []?Texture2D,

    default_scene: ?usize = null,

    pub fn load(allocator: std.mem.Allocator, file_dir: std.fs.Dir, file_path: []const u8) !Self {
        var gltf_file = zgltf.init(allocator);
        defer gltf_file.deinit();

        const parent_path = std.fs.path.dirname(file_path) orelse ".";
        const parent_dir = try file_dir.openDir(parent_path, .{});

        const file_buffer = try file_dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
        defer allocator.free(file_buffer);
        try gltf_file.parse(file_buffer);

        //TODO: load .bin if not .glb
        var bin_buffer: []align(4) const u8 = &.{};
        defer allocator.free(bin_buffer);
        if (gltf_file.glb_binary == null) {
            const bin_path = try replaceExt(allocator, file_path, ".bin");
            defer allocator.free(bin_path);

            bin_buffer = try file_dir.readFileAllocOptions(allocator, bin_path, std.math.maxInt(usize), null, 4, null);
            gltf_file.glb_binary = bin_buffer;
        }

        var meshes = try allocator.alloc(?Mesh, gltf_file.data.meshes.items.len);
        for (gltf_file.data.meshes.items, 0..) |*gltf_mesh, i| {
            meshes[i] = loadGltfMesh(allocator, &gltf_file, gltf_mesh) catch |err| val: {
                std.log.err("Failed to load {s} mesh {}: {}", .{ file_path, i, err });
                break :val null;
            };
        }

        var textures = try allocator.alloc(?Texture2D, gltf_file.data.images.items.len);
        for (gltf_file.data.images.items, 0..) |*gltf_image, i| {
            textures[i] = loadGltfTexture(allocator, parent_dir, gltf_image, i) catch |err| val: {
                std.log.err("Failed to load {s} textures {}: {}", .{ file_path, i, err });
                break :val null;
            };
        }

        var scenes = try allocator.alloc(?Scene, gltf_file.data.scenes.items.len);
        for (gltf_file.data.scenes.items, 0..) |*glft_scene, i| {
            scenes[i] = Scene.init(allocator, &gltf_file.data, glft_scene) catch |err| val: {
                std.log.err("Failed to load {s} scene {}: {}", .{ file_path, i, err });
                break :val null;
            };
        }

        return .{
            .allocator = allocator,
            .meshes = meshes,
            .textures = textures,
            .scenes = scenes,
            .default_scene = gltf_file.data.scene,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.scenes) |scene_opt| {
            if (scene_opt) |scene| {
                scene.deinit(self.allocator);
            }
        }
        self.allocator.free(self.scenes);

        for (self.meshes) |mesh_opt| {
            if (mesh_opt) |mesh| {
                mesh.deinit(self.allocator);
            }
        }
        self.allocator.free(self.meshes);

        for (self.textures) |texture_opt| {
            if (texture_opt) |texture| {
                texture.deinit(self.allocator);
            }
        }
        self.allocator.free(self.textures);
    }
};

pub const Scene = struct {
    const Self = @This();

    name: []u8,

    fn init(allocator: std.mem.Allocator, gltf_data: *const zgltf.Data, gltf_scene: *const zgltf.Scene) !Self {
        _ = gltf_data;

        return .{
            .name = try allocator.dupe(u8, gltf_scene.name),
        };
    }

    fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

fn loadGltfMesh(allocator: std.mem.Allocator, gltf_file: *const zgltf, gltf_mesh: *const zgltf.Mesh) !Mesh {
    var name = try std.ArrayList(u8).initCapacity(allocator, gltf_mesh.name.len);
    name.appendSliceAssumeCapacity(gltf_mesh.name);

    const primitives = try allocator.alloc(Mesh.Primitive, gltf_mesh.primitives.items.len);
    errdefer allocator.free(primitives);

    var positions: std.ArrayList(Mesh.VertexPositions) = .init(allocator);
    var attributes: std.ArrayList(Mesh.VertexAttributes) = .init(allocator);
    var indices: std.ArrayList(u32) = .init(allocator);

    for (gltf_mesh.primitives.items, 0..) |primitive, i| {
        var mesh_primitive = try loadGltfPrimitive(allocator, gltf_file, &primitive);
        defer mesh_primitive.deinit();

        const vertex_offset: u32 = @intCast(positions.items.len);
        const index_offset: u32 = @intCast(indices.items.len);
        const index_count: u32 = @intCast(mesh_primitive.indices.items.len);

        try positions.appendSlice(mesh_primitive.positions.items);
        try attributes.appendSlice(mesh_primitive.attributes.items);
        try indices.ensureTotalCapacity(indices.items.len + mesh_primitive.indices.items.len);
        for (mesh_primitive.indices.items) |index| {
            indices.appendAssumeCapacity(index + vertex_offset);
        }

        primitives[i] = .{
            .index_offset = index_offset,
            .index_count = index_count,
        };
    }

    return .{
        .name = try allocator.dupe(u8, gltf_mesh.name),
        .primitives = primitives,
        .positions = try positions.toOwnedSlice(),
        .attributes = try attributes.toOwnedSlice(),
        .indices = try indices.toOwnedSlice(),
    };
}

fn loadGltfTexture(allocator: std.mem.Allocator, parent_dir: std.fs.Dir, gltf_image: *const zgltf.Image, index: usize) !Texture2D {
    if (gltf_image.data) |data| {
        const image_name = try std.fmt.allocPrint(allocator, "image_{}", .{index});
        defer allocator.free(image_name);
        return stbi.load(allocator, gltf_image.uri orelse image_name, data);
    }

    if (gltf_image.uri) |uri| {
        return stbi.loadFromFile(allocator, parent_dir, uri);
    }

    return error.NoImageSource;
}

const PrimitiveData = struct {
    default_material: ?usize = null,
    positions: std.ArrayList(Mesh.VertexPositions),
    attributes: std.ArrayList(Mesh.VertexAttributes),
    indices: std.ArrayList(u32),

    fn deinit(self: *@This()) void {
        self.positions.deinit();
        self.attributes.deinit();
        self.indices.deinit();
    }
};

fn loadGltfPrimitive(allocator: std.mem.Allocator, gltf_file: *const zgltf, gltf_primitive: *const zgltf.Primitive) !PrimitiveData {
    var indices = std.ArrayList(u32).init(allocator);
    errdefer indices.deinit();

    if (gltf_primitive.indices) |indices_index| {
        const accessor = gltf_file.data.accessors.items[indices_index];
        std.debug.assert(accessor.type == .scalar);

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
    }

    var positions = std.ArrayList([3]f32).init(allocator);
    errdefer positions.deinit();

    var normals = std.ArrayList([3]f32).init(allocator);
    defer positions.deinit();

    var tangents = std.ArrayList([4]f32).init(allocator);
    defer positions.deinit();

    var uvs = std.ArrayList([2]f32).init(allocator);
    defer positions.deinit();

    for (gltf_primitive.attributes.items) |attribute| {
        switch (attribute) {
            .position => |index| {
                std.debug.assert(positions.items.len == 0);
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec3);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                try positions.ensureTotalCapacity(it.total_count);
                while (it.next()) |position_slice| {
                    positions.appendAssumeCapacity(.{ position_slice[0], position_slice[1], position_slice[2] });
                }
            },
            .normal => |index| {
                std.debug.assert(normals.items.len == 0);
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec3);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                try normals.ensureTotalCapacity(it.total_count);
                while (it.next()) |normal_slice| {
                    normals.appendAssumeCapacity(.{ normal_slice[0], normal_slice[1], normal_slice[2] });
                }
            },
            .tangent => |index| {
                std.debug.assert(tangents.items.len == 0);
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec4);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                try tangents.ensureTotalCapacity(it.total_count);
                while (it.next()) |tangent_slice| {
                    tangents.appendAssumeCapacity(.{ tangent_slice[0], tangent_slice[1], tangent_slice[2], tangent_slice[3] });
                }
            },
            .texcoord => |index| {
                // Uv2s not supported yet
                if (uvs.items.len != 0)
                    continue;

                std.debug.assert(uvs.items.len == 0);
                const accessor = gltf_file.data.accessors.items[index];
                std.debug.assert(accessor.type == .vec2);
                std.debug.assert(accessor.component_type == .float);
                var it = accessor.iterator(f32, gltf_file, gltf_file.glb_binary.?);
                try uvs.ensureTotalCapacity(it.total_count);
                while (it.next()) |uv_slice| {
                    uvs.appendAssumeCapacity(.{ uv_slice[0], uv_slice[1] });
                }
            },
            else => {},
        }
    }

    var attributes = std.ArrayList(Mesh.VertexAttributes).init(allocator);
    errdefer attributes.deinit();
    try attributes.resize(positions.items.len);

    for (attributes.items, normals.items) |*attribute, normal| {
        attribute.normal = normal;
    }

    if (tangents.items.len != 0) {
        for (attributes.items, tangents.items) |*attribute, tangent| {
            attribute.tangent = tangent;
        }
    } else {
        //TODO: gen tangets if non are provided
        for (attributes.items) |*attribute| {
            attribute.tangent = .{ 0, 0, 0, 0 };
        }
    }

    for (attributes.items, uvs.items) |*attribute, uv| {
        attribute.uv0 = uv;
    }

    return .{
        .positions = positions,
        .attributes = attributes,
        .indices = indices,
    };
}
