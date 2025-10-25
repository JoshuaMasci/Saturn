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

/// Loads the scene till the transfer queue is full
/// Returns false if the transfer queue is full
/// Returns true when all loading is done
/// TODO: progress info
pub fn tryLoadSceneAssets(self: *Self, temp_allocator: std.mem.Allocator, scene: *const RenderScene) bool {
    for (scene.instances.items) |instance| {
        if (!self.tryLoadMesh(temp_allocator, instance.component.mesh)) return false;

        for (instance.component.materials.constSlice()) |material| {
            if (!self.tryLoadMaterial(temp_allocator, material)) return false;
        }
    }

    self.updateBuffers(temp_allocator) catch |err| std.log.err("Failed to update resource buffers: {}", .{err});
    return true;
}

/// Returns true when loaded
pub fn tryLoadMesh(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) bool {
    const load_meshlets = self.backend.device.extensions.mesh_shader;

    if (!self.meshes.map.contains(handle)) {
        if (self.registry.loadAsset(
            MeshAsset,
            temp_allocator,
            handle,
            .{ .load_meshlets = load_meshlets },
        )) |mesh| {
            defer mesh.deinit(temp_allocator);

            if (!self.meshes.canUploadMesh(&mesh)) {
                return false;
            }

            self.meshes.addMesh(handle, &mesh) catch |err| {
                std.log.err("Failed to upload mesh {}", .{err});
                return false;
            };
        } else |err| {
            std.log.err("Failed to load mesh {}", .{err});
            return false;
        }
    }

    return true;
}

/// Returns true when loaded
pub fn tryLoadMaterial(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) bool {
    if (!self.material_map.contains(handle)) {
        if (self.registry.loadAsset(MaterialAsset, temp_allocator, handle, .{})) |material| {
            defer material.deinit(temp_allocator);

            var gpu_pack = MaterialAsset.Gpu.pack(material);

            if (material.base_color_texture) |texture_handle| {
                if (!self.tryLoadTexture(temp_allocator, texture_handle)) return false;
                gpu_pack.base_color_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            if (material.metallic_roughness_texture) |texture_handle| {
                if (!self.tryLoadTexture(temp_allocator, texture_handle)) return false;
                gpu_pack.metallic_roughness_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            if (material.emissive_texture) |texture_handle| {
                if (!self.tryLoadTexture(temp_allocator, texture_handle)) return false;
                gpu_pack.emissive_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            if (material.occlusion_texture) |texture_handle| {
                if (!self.tryLoadTexture(temp_allocator, texture_handle)) return false;
                gpu_pack.occlusion_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            if (material.normal_texture) |texture_handle| {
                if (!self.tryLoadTexture(temp_allocator, texture_handle)) return false;
                gpu_pack.normal_texture = self.tryGetTextureSampledBinding(texture_handle);
            }

            //Need material to have longer lifetime
            const final_material = material.dupe(self.allocator) catch |err| {
                std.log.err("Failed to dupe material {}", .{err});
                return false;
            };

            self.material_map.put(handle, .{
                .material = final_material,
                .gpu = gpu_pack,
            }) catch |err| {
                std.log.err("Failed to append material to list {}", .{err});
                return false;
            };
        } else |err| {
            std.log.err("Failed to load material {}", .{err});
            return false;
        }
    }
    return true;
}

/// Returns true when loaded
pub fn tryLoadTexture(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) bool {
    if (!self.texture_map.contains(handle)) {
        if (self.registry.loadAsset(TextureAsset, temp_allocator, handle, .{})) |texture| {
            defer texture.deinit(temp_allocator);

            const format: vk.Format = switch (texture.format) {
                .r8 => .r8_unorm,
                .rg8 => .r8g8_unorm,
                .rgba8 => .r8g8b8a8_unorm,
            };

            if (!self.canUploadTexture(&texture)) {
                return false;
            }

            const texture_handle = self.backend.createImageWithData(texture.name, .{ texture.width, texture.height }, format, .{ .sampled_bit = true }, texture.data) catch |err| {
                std.log.err("Failed to create and upload texture {}", .{err});
                return false;
            };

            self.texture_map.put(handle, .{
                .image_handle = texture_handle,
            }) catch |err| {
                self.backend.destroyImage(texture_handle);
                std.log.err("Failed to append texture to list {}", .{err});
                return false;
            };
        } else |err| {
            std.log.err("Failed to load texture {}", .{err});
            return false;
        }
    }

    return true;
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

fn canUploadTexture(self: *const Self, texture: *const TextureAsset) bool {
    //Can always upload if host_image_copy is enabled
    return self.backend.device.extensions.host_image_copy or self.backend.getTransferQueue().hasSpace(texture.data.len);
}
