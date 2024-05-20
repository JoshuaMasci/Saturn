const std = @import("std");
const zmesh = @import("zmesh");
const gltf = zmesh.io.zcgltf;

const zstbi = @import("zstbi");

const backend = @import("renderer/renderer.zig");

const TexturedVertex = @import("renderer/opengl/vertex.zig").TexturedVertex;
const Texture = @import("renderer/opengl/texture.zig");
const Mesh = @import("renderer/opengl/mesh.zig");

const ImageMap = std.AutoHashMap(*gltf.Image, zstbi.Image);

pub const GltfResources = struct {
    textures: std.ArrayList(?backend.TextureHandle),
    materials: std.ArrayList(?backend.MaterialHandle),
    meshes: std.ArrayList(?backend.StaticMeshHandle),

    pub fn deinit(self: @This()) void {
        self.textures.deinit();
        self.materials.deinit();
        self.meshes.deinit();
    }
};

pub fn load(allocator: std.mem.Allocator, renderer: *backend.Renderer, file_path: [:0]const u8) !GltfResources {
    const start = std.time.Instant.now() catch unreachable;
    defer {
        const end = std.time.Instant.now() catch unreachable;
        const time_ns: f32 = @floatFromInt(end.since(start));
        std.log.info("loading file {s} took: {d:.3}ms", .{ file_path, time_ns / std.time.ns_per_ms });
    }

    const parent_path = std.fs.path.dirname(file_path) orelse ".";

    zmesh.init(allocator);
    defer zmesh.deinit();

    const data = try zmesh.io.parseAndLoadFile(file_path);
    defer zmesh.io.freeData(data);

    var images = try std.ArrayList(?zstbi.Image).initCapacity(allocator, data.images_count);
    defer {
        for (images.items) |*image_opt| {
            if (image_opt.*) |*image| {
                image.deinit();
            }
        }
        images.deinit();
    }

    if (data.images) |gltf_images| {
        for (gltf_images[0..data.images_count], 0..) |*glft_image, i| {
            if (load_gltf_image(allocator, parent_path, glft_image)) |image_opt| {
                images.appendAssumeCapacity(image_opt);
            } else |err| {
                std.log.err("Failed to load {s} image {}: {}", .{ file_path, i, err });
                images.appendAssumeCapacity(null);
            }
        }
    }

    var textures = try std.ArrayList(?backend.TextureHandle).initCapacity(allocator, data.textures_count);
    if (data.textures) |gltf_textures| {
        for (gltf_textures[0..data.textures_count], 0..) |gltf_texture, i| {
            if (load_gltf_texture(renderer, data, images.items, &gltf_texture)) |texture| {
                textures.appendAssumeCapacity(texture);
            } else |err| {
                std.log.err("Failed to load {s} texture {}: {}", .{ file_path, i, err });
                textures.appendAssumeCapacity(null);
            }
        }
    }

    var materials = try std.ArrayList(?backend.MaterialHandle).initCapacity(allocator, data.materials_count);
    if (data.materials) |gltf_materials| {
        for (gltf_materials[0..data.materials_count], 0..) |gltf_material, i| {
            if (load_gltf_material(renderer, data, textures.items, &gltf_material)) |material| {
                materials.appendAssumeCapacity(material);
            } else |err| {
                std.log.err("Failed to load {s} material {}: {}", .{ file_path, i, err });
                materials.appendAssumeCapacity(null);
            }
        }
    }

    var meshes = try std.ArrayList(?backend.StaticMeshHandle).initCapacity(allocator, data.meshes_count);
    if (data.meshes) |gltf_meshes| {
        for (gltf_meshes[0..data.meshes_count], 0..) |*glft_mesh, i| {
            if (load_gltf_mesh(allocator, renderer, glft_mesh)) |mesh_opt| {
                meshes.appendAssumeCapacity(mesh_opt);
            } else |err| {
                std.log.err("Failed to load {s} mesh {}: {}", .{ file_path, i, err });
                meshes.appendAssumeCapacity(null);
            }
        }
    }

    return .{
        .textures = textures,
        .materials = materials,
        .meshes = meshes,
    };
}

fn load_gltf_image(allocator: std.mem.Allocator, parent_path: []const u8, gltf_image: *const gltf.Image) !?zstbi.Image {
    var image_opt: ?zstbi.Image = null;

    if (gltf_image.buffer_view) |buffer_view| {
        const bytes_ptr: [*]u8 = @ptrCast(buffer_view.buffer.data.?);
        const bytes: []u8 = bytes_ptr[buffer_view.offset..(buffer_view.offset + buffer_view.size)];
        image_opt = zstbi.Image.loadFromMemory(bytes, 0) catch std.debug.panic("", .{});
    }

    if (gltf_image.uri) |uri| {
        const uri_len = std.mem.len(uri);
        const uri_slice = uri[0..uri_len];

        var full_path = std.ArrayList(u8).init(allocator);
        defer full_path.deinit();
        try full_path.appendSlice(parent_path);
        try full_path.append('/');
        try full_path.appendSlice(uri_slice);
        try full_path.append(0);
        image_opt = try zstbi.Image.loadFromFile(full_path.items[0..(full_path.items.len - 1) :0], 4);
    }

    if (image_opt == null) {
        std.log.err("gltf image doesn't contain a source (either buffer view or uri)", .{});
    }

    return image_opt;
}

fn load_gltf_texture(renderer: *backend.Renderer, data: *gltf.Data, images: []?zstbi.Image, gltf_texture: *const gltf.Texture) !backend.TextureHandle {
    const image_index = data.image_index(gltf_texture.image) orelse return error.NoImageForTexture;
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
    std.debug.assert(image.bytes_per_component == 1);
    const pixel_type: Texture.PixelType = .u8;

    var sampler = Texture.Sampler{};
    if (gltf_texture.sampler) |gltf_sampler| {
        sampler.min = switch (gltf_sampler.min_filter) {
            9728 => .Nearest,
            9729 => .Linear,
            9984 => .Nearest_Mip_Nearest,
            9985 => .Linear_Mip_Nearest,
            9986 => .Nearest_Mip_Linear,
            9987 => .Linear_Mip_Linear,
            else => .Linear,
        };

        sampler.mag = switch (gltf_sampler.mag_filter) {
            9728 => .Nearest,
            9729 => .Linear,
            else => .Linear,
        };

        sampler.address_mode_u = switch (gltf_sampler.wrap_s) {
            33071 => .Clamp_To_Edge,
            33648 => .Mirrored_Repeat,
            10497 => .Repeat,
            else => .Repeat,
        };

        sampler.address_mode_v = switch (gltf_sampler.wrap_t) {
            33071 => .Clamp_To_Edge,
            33648 => .Mirrored_Repeat,
            10497 => .Repeat,
            else => .Repeat,
        };
    }

    const texture = Texture.init(
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

fn get_material_texture(data: *gltf.Data, textures: []?backend.TextureHandle, view: *const gltf.TextureView) ?backend.TextureHandle {
    const index = data.texture_index(view.texture) orelse return null;
    return textures[index];
}

fn load_gltf_material(renderer: *backend.Renderer, data: *gltf.Data, textures: []?backend.TextureHandle, gltf_material: *const gltf.Material) !backend.MaterialHandle {
    var material: backend.Material = .{};

    if (gltf_material.has_pbr_metallic_roughness != 0) {
        material.base_color_factor = gltf_material.pbr_metallic_roughness.base_color_factor;
        material.base_color_texture = get_material_texture(data, textures, &gltf_material.pbr_metallic_roughness.base_color_texture);

        material.metallic_roughness_factor = .{ gltf_material.pbr_metallic_roughness.metallic_factor, gltf_material.pbr_metallic_roughness.roughness_factor };
        material.metallic_roughness_texture = get_material_texture(data, textures, &gltf_material.pbr_metallic_roughness.metallic_roughness_texture);
    }

    material.normal_texture = get_material_texture(data, textures, &gltf_material.normal_texture);

    material.occlusion_texture = get_material_texture(data, textures, &gltf_material.occlusion_texture);

    material.emissive_factor = gltf_material.emissive_factor;
    material.emissive_factor[0] *= gltf_material.emissive_strength.emissive_strength;
    material.emissive_factor[1] *= gltf_material.emissive_strength.emissive_strength;
    material.emissive_factor[2] *= gltf_material.emissive_strength.emissive_strength;
    material.emissive_texture = get_material_texture(data, textures, &gltf_material.emissive_texture);

    return try renderer.load_material(material);
}

pub fn load_gltf_mesh(allocator: std.mem.Allocator, renderer: *backend.Renderer, gltf_mesh: *const gltf.Mesh) !backend.StaticMeshHandle {
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

    for (gltf_mesh.primitives[0..gltf_mesh.primitives_count]) |*primitive| {
        try appendMeshPrimitive(
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

pub fn appendMeshPrimitive(
    primitive: *const gltf.Primitive,
    indices: *std.ArrayList(u32),
    positions: *std.ArrayList([3]f32),
    normals: ?*std.ArrayList([3]f32),
    texcoords0: ?*std.ArrayList([2]f32),
    tangents: ?*std.ArrayList([4]f32),
) !void {
    const prim = primitive;

    const num_vertices: u32 = @as(u32, @intCast(prim.attributes[0].data.count));
    const num_indices: u32 = @as(u32, @intCast(prim.indices.?.count));

    // Indices.
    {
        try indices.ensureTotalCapacity(indices.items.len + num_indices);

        const accessor = prim.indices.?;
        const buffer_view = accessor.buffer_view.?;

        std.debug.assert(accessor.stride == buffer_view.stride or buffer_view.stride == 0);
        std.debug.assert(accessor.stride * accessor.count <= buffer_view.size);
        std.debug.assert(buffer_view.buffer.data != null);

        const data_addr = @as([*]const u8, @ptrCast(buffer_view.buffer.data)) +
            accessor.offset + buffer_view.offset;

        if (accessor.stride == 1) {
            std.debug.assert(accessor.component_type == .r_8u);
            const src = @as([*]const u8, @ptrCast(data_addr));
            var i: u32 = 0;
            while (i < num_indices) : (i += 1) {
                indices.appendAssumeCapacity(src[i]);
            }
        } else if (accessor.stride == 2) {
            std.debug.assert(accessor.component_type == .r_16u);
            const src = @as([*]const u16, @ptrCast(@alignCast(data_addr)));
            var i: u32 = 0;
            while (i < num_indices) : (i += 1) {
                indices.appendAssumeCapacity(src[i]);
            }
        } else if (accessor.stride == 4) {
            std.debug.assert(accessor.component_type == .r_32u);
            const src = @as([*]const u32, @ptrCast(@alignCast(data_addr)));
            var i: u32 = 0;
            while (i < num_indices) : (i += 1) {
                indices.appendAssumeCapacity(src[i]);
            }
        } else {
            unreachable;
        }
    }

    // Attributes.
    {
        const attributes = prim.attributes[0..prim.attributes_count];
        for (attributes) |attrib| {
            const accessor = attrib.data;
            std.debug.assert(accessor.component_type == .r_32f);

            const buffer_view = accessor.buffer_view.?;
            std.debug.assert(buffer_view.buffer.data != null);

            std.debug.assert(accessor.stride == buffer_view.stride or buffer_view.stride == 0);
            std.debug.assert(accessor.stride * accessor.count <= buffer_view.size);

            const data_addr = @as([*]const u8, @ptrCast(buffer_view.buffer.data)) +
                accessor.offset + buffer_view.offset;

            if (attrib.type == .position) {
                std.debug.assert(accessor.type == .vec3);
                const slice = @as([*]const [3]f32, @ptrCast(@alignCast(data_addr)))[0..num_vertices];
                try positions.appendSlice(slice);
            } else if (attrib.type == .normal) {
                if (normals) |n| {
                    std.debug.assert(accessor.type == .vec3);
                    const slice = @as([*]const [3]f32, @ptrCast(@alignCast(data_addr)))[0..num_vertices];
                    try n.appendSlice(slice);
                }
            } else if (attrib.type == .texcoord and attrib.index == 0) {
                if (texcoords0) |tc| {
                    std.debug.assert(accessor.type == .vec2);
                    const slice = @as([*]const [2]f32, @ptrCast(@alignCast(data_addr)))[0..num_vertices];
                    try tc.appendSlice(slice);
                }
            } else if (attrib.type == .tangent) {
                if (tangents) |tan| {
                    std.debug.assert(accessor.type == .vec4);
                    const slice = @as([*]const [4]f32, @ptrCast(@alignCast(data_addr)))[0..num_vertices];
                    try tan.appendSlice(slice);
                }
            }
        }
    }
}
