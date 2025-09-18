const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MaterialAsset = @import("../asset/material.zig");
const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const TextureAsset = @import("../asset/texture.zig");
const RenderScene = @import("scene.zig").RenderScene;
const Device = @import("vulkan/device.zig");
const GpuImage = @import("vulkan/image.zig");
const GpuMesh = @import("vulkan/mesh.zig");
const rg = @import("vulkan/render_graph.zig");

const Self = @This();

allocator: std.mem.Allocator,
registry: *const AssetRegistry,
device: *Device,

static_mesh_map: std.AutoArrayHashMap(AssetRegistry.AssetHandle, struct {
    mesh: GpuMesh,
}),
texture_map: std.AutoArrayHashMap(AssetRegistry.Handle, struct {
    image_handle: Device.ImageHandle,
    //TODO: bindings?
}),
material_map: std.AutoArrayHashMap(AssetRegistry.Handle, struct {
    material: MaterialAsset,
    buffer_index: u32,
}),

material_buffer: MaterialBuffer,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    device: *Device,
) Self {
    return .{
        .allocator = allocator,
        .registry = registry,
        .device = device,

        .static_mesh_map = .init(allocator),
        .texture_map = .init(allocator),
        .material_map = .init(allocator),
        .material_buffer = .{},
    };
}

pub fn deinit(self: *Self) void {
    for (self.static_mesh_map.values()) |entry| {
        entry.mesh.deinit();
    }
    self.static_mesh_map.deinit();

    for (self.texture_map.values()) |entry| {
        self.device.destroyImage(entry.image_handle);
    }
    self.texture_map.deinit();

    for (self.material_map.values()) |entry| {
        entry.material.deinit(self.allocator);
    }
    self.material_map.deinit();
}

pub fn createMaterialBuffer(self: Self, temp_allocator: std.mem.Allocator, render_graph: *rg.RenderGraph) !rg.RenderGraphBufferHandle {
    const temp_slice_ptr: *[]MaterialAsset.Gpu = try temp_allocator.create([]MaterialAsset.Gpu);

    temp_slice_ptr.* = try temp_allocator.dupe(MaterialAsset.Gpu, self.material_buffer.getSlice());
    const temp_slice_size: usize = @sizeOf(MaterialAsset.Gpu) * temp_slice_ptr.len;

    const temp_buffer = try render_graph.createTransientBuffer(.{
        .location = .gpu_only,
        .size = temp_slice_size,
        .usage = .{
            .storage_buffer_bit = true,
            .transfer_dst_bit = true,
        },
    });

    try render_graph.buffer_upload_passes.append(render_graph.allocator, .{
        .target = temp_buffer,
        .offset = 0,
        .size = temp_slice_size,
        .write_data = @ptrCast(temp_slice_ptr),
        .write_fn = rg.SliceUploadFn(MaterialAsset.Gpu).uploadFn,
    });

    return temp_buffer;
}

pub fn loadSceneAssets(self: *Self, temp_allocator: std.mem.Allocator, scene: *const RenderScene) void {
    for (scene.static_meshes.items) |static_mesh| {
        self.tryLoadMesh(temp_allocator, static_mesh.component.mesh);

        for (static_mesh.component.materials.constSlice()) |material| {
            self.tryLoadMaterial(temp_allocator, material);
        }
    }
}

pub fn tryLoadMesh(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) void {
    if (!self.static_mesh_map.contains(handle)) {
        if (self.registry.loadAsset(MeshAsset, temp_allocator, handle)) |mesh| {
            defer mesh.deinit(temp_allocator);
            const gpu_mesh = GpuMesh.init(self.allocator, self.device, &mesh) catch return;

            self.static_mesh_map.put(handle, .{
                .mesh = gpu_mesh,
            }) catch |err| {
                gpu_mesh.deinit();
                std.log.err("Failed to append static mesh to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load static mesh {}", .{err});
        }
    }
}

pub fn tryLoadTexture(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) void {
    if (!self.texture_map.contains(handle)) {
        if (self.registry.loadAsset(TextureAsset, temp_allocator, handle)) |texture| {
            defer texture.deinit(temp_allocator);

            const format: vk.Format = switch (texture.format) {
                .r8 => .r8_unorm,
                .rg8 => .r8g8_unorm,
                .rgba8 => .r8g8b8a8_unorm,
            };

            const image_handle = self.device.createImageWithData(.{ texture.width, texture.height }, format, .{ .transfer_dst_bit = true, .sampled_bit = true }, texture.data) catch return;

            self.texture_map.put(handle, .{
                .image_handle = image_handle,
            }) catch |err| {
                self.device.destroyImage(image_handle);
                std.log.err("Failed to append texture to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load texture {}", .{err});
        }
    }
}

fn tryGetTextureSampledBinding(self: *const Self, handle: AssetRegistry.Handle) u32 {
    if (self.texture_map.get(handle)) |entry| {
        if (self.device.images.get(entry.image_handle)) |image| {
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
        if (self.registry.loadAsset(MaterialAsset, self.allocator, handle)) |material| {
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

            const buffer_index = self.material_buffer.add(gpu_pack);

            self.material_map.put(handle, .{
                .material = material,
                .buffer_index = buffer_index,
            }) catch |err| {
                std.log.err("Failed to append material to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load material {}", .{err});
        }
    }
}

const MaterialBuffer = struct {
    next_index: u32 = 0,
    cpu_buffer: [2048]MaterialAsset.Gpu = std.mem.zeroes([2048]MaterialAsset.Gpu),

    fn add(self: *@This(), mat: MaterialAsset.Gpu) u32 {
        const i = self.next_index;
        defer self.next_index += 1;

        self.cpu_buffer[i] = mat;

        return i;
    }

    fn getSlice(self: *const @This()) []const MaterialAsset.Gpu {
        return self.cpu_buffer[0..self.next_index];
    }
};
