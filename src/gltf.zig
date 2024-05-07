const std = @import("std");
const zmesh = @import("zmesh");
const zstbi = @import("zstbi");

const backend = @import("renderer/renderer.zig");

const TexturedVertex = @import("renderer/opengl/vertex.zig").TexturedVertex;
const Texture = @import("renderer/opengl/texture.zig");
const Mesh = @import("renderer/opengl/mesh.zig");

const ImageMap = std.AutoHashMap(*zmesh.io.zcgltf.Image, zstbi.Image);

pub fn load(allocator: std.mem.Allocator, renderer: *backend.Renderer, file_path: [:0]const u8) !void {
    const start = std.time.Instant.now() catch unreachable;
    defer {
        const end = std.time.Instant.now() catch unreachable;
        const time_ns: f32 = @floatFromInt(end.since(start));
        std.log.info("loading file {s} took: {d:.3}ms", .{ file_path, time_ns / std.time.ns_per_ms });
    }

    zmesh.init(allocator);
    defer zmesh.deinit();

    const data = try zmesh.io.parseAndLoadFile(file_path);
    defer zmesh.io.freeData(data);

    var images = ImageMap.init(allocator);
    defer {
        var iter = images.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        images.deinit();
    }

    if (data.images) |gltf_images| {
        for (gltf_images[0..data.images_count], 0..) |*glft_image, i| {
            if (load_gltf_image(glft_image)) |image_opt| {
                if (image_opt) |image| {
                    try images.put(glft_image, image);
                }
            } else |err| {
                std.log.err("Failed to load {s} image {}: {}", .{ file_path, i, err });
            }
        }
    }

    var textures = try std.ArrayList(?backend.TextureHandle).initCapacity(allocator, data.textures_count);
    defer textures.deinit();

    if (data.textures) |gltf_textures| {
        for (gltf_textures[0..data.textures_count], 0..) |gltf_texture, i| {
            if (load_gltf_texture(renderer, &images, &gltf_texture)) |loaded_image| {
                textures.appendAssumeCapacity(loaded_image);
            } else |err| {
                std.log.err("Failed to load {s} texture {}: {}", .{ file_path, i, err });
                textures.appendAssumeCapacity(null);
            }
        }
    }
}

fn load_gltf_image(gltf_image: *const zmesh.io.zcgltf.Image) !?zstbi.Image {
    var image_opt: ?zstbi.Image = null;

    if (gltf_image.buffer_view) |buffer_view| {
        const bytes_ptr: [*]u8 = @ptrCast(buffer_view.buffer.data.?);
        const bytes: []u8 = bytes_ptr[buffer_view.offset..(buffer_view.offset + buffer_view.size)];
        image_opt = zstbi.Image.loadFromMemory(bytes, 0) catch std.debug.panic("", .{});
    }

    if (gltf_image.uri) |uri| {
        std.log.info("TODO: load image from uri: {s}", .{uri});
    }

    if (image_opt == null) {
        std.log.err("gltf image doesn't contain a source (either buffer view or uri)", .{});
    }

    return image_opt;
}

fn load_gltf_texture(renderer: *backend.Renderer, images: *ImageMap, gltf_texture: *const zmesh.io.zcgltf.Texture) !backend.TextureHandle {
    const image = &images.get(gltf_texture.image.?).?;

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
            else => unreachable,
        };

        sampler.mag = switch (gltf_sampler.mag_filter) {
            9728 => .Nearest,
            9729 => .Linear,
            else => unreachable,
        };

        sampler.address_mode_u = switch (gltf_sampler.wrap_s) {
            33071 => .Clamp_To_Edge,
            33648 => .Mirrored_Repeat,
            10497 => .Repeat,
            else => unreachable,
        };

        sampler.address_mode_v = switch (gltf_sampler.wrap_t) {
            33071 => .Clamp_To_Edge,
            33648 => .Mirrored_Repeat,
            10497 => .Repeat,
            else => unreachable,
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

fn load_gltf_material(renderer: *backend.Renderer, gltf_material: *const zmesh.io.zcgltf.Material) !backend.MaterialHandle {
    _ = renderer;
    _ = gltf_material;
}

pub fn load_gltf_mesh(allocator: std.mem.Allocator, file_path: [:0]const u8, renderer: *backend.Renderer) !backend.StaticMeshHandle {
    const start = std.time.Instant.now() catch unreachable;
    defer {
        const end = std.time.Instant.now() catch unreachable;
        const time_ns: f32 = @floatFromInt(end.since(start));
        std.log.info("{s} loading took: {d:.3}ms", .{ file_path, time_ns / std.time.ns_per_ms });
    }

    zmesh.init(allocator);
    defer zmesh.deinit();

    const data = try zmesh.io.parseAndLoadFile(file_path);
    defer zmesh.io.freeData(data);

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

    try zmesh.io.appendMeshPrimitive(
        data,
        0,
        0,
        &mesh_indices,
        &mesh_positions,
        &mesh_normals,
        &mesh_uv0s,
        &mesh_tangents,
    );

    var mesh_vertices = try std.ArrayList(TexturedVertex).initCapacity(allocator, mesh_positions.items.len);
    defer mesh_vertices.deinit();

    for (mesh_positions.items, mesh_normals.items, mesh_tangents.items, mesh_uv0s.items) |position, normal, tangent, uv0| {
        mesh_vertices.appendAssumeCapacity(.{
            .position = position,
            .normal = normal,
            .tangent = tangent,
            .uv0 = uv0,
        });
    }

    std.log.info("{} Vertices {} Indices", .{ mesh_positions.items.len, mesh_indices.items.len });
    const mesh = Mesh.init(TexturedVertex, u32, mesh_vertices.items, mesh_indices.items);
    return try renderer.static_meshes.insert(mesh);
}
