const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MaterialAsset = @import("../asset/material.zig");
const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const TextureAsset = @import("../asset/texture.zig");
const RenderScene = @import("scene.zig");
const Backend = @import("vulkan/backend.zig");
const GpuImage = @import("vulkan/image.zig");
const rg = @import("vulkan/render_graph.zig");
const UnifiedGeometryBuffer = @import("unified_geometry_buffer.zig");

const Self = @This();

allocator: std.mem.Allocator,
registry: *const AssetRegistry,
backend: *Backend,

meshes: UnifiedGeometryBuffer,

texture_map: std.AutoArrayHashMap(AssetRegistry.Handle, struct {
    image_handle: Backend.ImageHandle,
    //TODO: bindings?
}),
material_map: std.AutoArrayHashMap(AssetRegistry.Handle, struct {
    material: MaterialAsset,
    gpu: MaterialAsset.Gpu,
    buffer_index: ?u32 = null,
}),

material_buffer: ?Backend.BufferHandle = null,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    backend: *Backend,
) !Self {
    const BytesPerGibibyte: usize = 1024 * 1024 * 1024;
    return .{
        .allocator = allocator,
        .registry = registry,
        .backend = backend,
        .meshes = try .init(allocator, registry, backend, BytesPerGibibyte * 1),
        .texture_map = .init(allocator),
        .material_map = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.meshes.deinit();

    if (self.material_buffer) |buffer| {
        self.backend.destroyBuffer(buffer);
    }

    for (self.texture_map.values()) |entry| {
        self.backend.destroyImage(entry.image_handle);
    }
    self.texture_map.deinit();

    for (self.material_map.values()) |entry| {
        entry.material.deinit(self.allocator);
    }
    self.material_map.deinit();
}

pub fn updateBuffers(self: *Self, temp_allocator: std.mem.Allocator) !void {
    //Material
    {
        if (self.material_buffer) |buffer| {
            self.backend.destroyBuffer(buffer);
            self.material_buffer = null;
        }

        const material_slice = try temp_allocator.alloc(MaterialAsset.Gpu, self.material_map.values().len);
        defer temp_allocator.free(material_slice);
        for (material_slice, self.material_map.values(), 0..) |*gpu, *entry, i| {
            gpu.* = entry.gpu;
            entry.buffer_index = @intCast(i);
        }
        self.material_buffer = try self.backend.createBufferWithData("material_info_buffer", .{ .storage_buffer_bit = true, .transfer_dst_bit = true }, std.mem.sliceAsBytes(material_slice));
    }
}

pub fn loadSceneAssets(self: *Self, temp_allocator: std.mem.Allocator, scene: *const RenderScene) void {
    for (scene.instances.items) |instance| {
        for (instance.component.materials.constSlice()) |material| {
            self.tryLoadMaterial(temp_allocator, material);
        }
        self.meshes.addMesh(instance.component.mesh);
    }

    self.updateBuffers(temp_allocator) catch |err| std.log.err("Failed to update resource buffers: {}", .{err});
}

pub fn tryLoadTexture(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) void {
    if (!self.texture_map.contains(handle)) {
        if (self.registry.loadAsset(TextureAsset, temp_allocator, handle, .{})) |texture| {
            defer texture.deinit(temp_allocator);

            const format: vk.Format = switch (texture.format) {
                .r8 => .r8_unorm,
                .rg8 => .r8g8_unorm,
                .rgba8 => .r8g8b8a8_unorm,
            };

            const image_handle = self.backend.createImageWithData(.{ texture.width, texture.height }, format, .{ .transfer_dst_bit = true, .sampled_bit = true }, texture.data) catch return;

            self.texture_map.put(handle, .{
                .image_handle = image_handle,
            }) catch |err| {
                self.backend.destroyImage(image_handle);
                std.log.err("Failed to append texture to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load texture {}", .{err});
        }
    }
}

fn tryGetTextureSampledBinding(self: *const Self, handle: AssetRegistry.Handle) u32 {
    if (self.texture_map.get(handle)) |entry| {
        if (self.backend.images.get(entry.image_handle)) |image| {
            if (image.sampled_binding) |binding| {
                return binding.index;
            }
        }
    }
    return 0;
}

pub fn tryLoadMaterial(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) void {
    if (!self.material_map.contains(handle)) {
        //Need to load the asset using the non temp allocator, otherwise the name will be invalid
        if (self.registry.loadAsset(MaterialAsset, self.allocator, handle, .{})) |material| {
            var gpu_pack = MaterialAsset.Gpu.pack(material);

            if (material.base_color_texture) |texture_handle| {
                self.tryLoadTexture(temp_allocator, texture_handle);
                gpu_pack.base_color_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            if (material.metallic_roughness_texture) |texture_handle| {
                self.tryLoadTexture(temp_allocator, texture_handle);
                gpu_pack.metallic_roughness_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            if (material.emissive_texture) |texture_handle| {
                self.tryLoadTexture(temp_allocator, texture_handle);
                gpu_pack.emissive_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            if (material.occlusion_texture) |texture_handle| {
                self.tryLoadTexture(temp_allocator, texture_handle);
                gpu_pack.occlusion_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            if (material.normal_texture) |texture_handle| {
                self.tryLoadTexture(temp_allocator, texture_handle);
                gpu_pack.normal_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            self.material_map.put(handle, .{
                .material = material,
                .gpu = gpu_pack,
            }) catch |err| {
                std.log.err("Failed to append material to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load material {}", .{err});
        }
    }
}
