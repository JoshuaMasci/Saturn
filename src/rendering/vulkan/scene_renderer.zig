const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MaterialAsset = @import("../../asset/material.zig");
const MeshAsset = @import("../../asset/mesh.zig");
const ShaderAsset = @import("../../asset/shader.zig");
const ShaderAssetHandle = ShaderAsset.Registry.Handle;
const Texture2dAsset = @import("../../asset/texture_2d.zig");
const global = @import("../../global.zig");
const c = @import("../../platform/sdl3.zig").c;
const Window = @import("../../platform/sdl3.zig").Window;
const Settings = @import("../../rendering/settings.zig");
const Transform = @import("../../transform.zig");
const Camera = @import("../camera.zig").Camera;
const RenderScene = @import("../scene.zig").RenderScene;

const Device = @import("device.zig");
const Mesh = @import("mesh.zig");

const Self = @This();

allocator: std.mem.Allocator,
device: *Device,

static_mesh_map: std.AutoArrayHashMap(MeshAsset.Registry.Handle, Mesh),
material_map: std.AutoArrayHashMap(MaterialAsset.Registry.Handle, MaterialAsset),

pub fn init(allocator: std.mem.Allocator, device: *Device) !Self {
    return .{
        .allocator = allocator,
        .device = device,
        .static_mesh_map = .init(allocator),
        .material_map = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.static_mesh_map.values()) |mesh| {
        mesh.deinit();
    }
    self.static_mesh_map.deinit();

    for (self.material_map.values()) |material| {
        material.deinit(self.allocator);
    }
    self.material_map.deinit();
}

pub fn render(self: *Self, command_buffer: vk.CommandBufferProxy, target_size: [2]u32, scene: *const RenderScene, camera: struct {
    transform: Transform,
    camera: Camera,
}) void {
    _ = self; // autofix
    _ = command_buffer; // autofix
    _ = target_size; // autofix
    _ = scene; // autofix
    _ = camera; // autofix
}

pub fn loadSceneData(self: *Self, temp_allocator: std.mem.Allocator, scene: *const RenderScene) void {
    for (scene.static_meshes.items) |static_mesh| {
        self.tryLoadMesh(temp_allocator, static_mesh.component.mesh);

        for (static_mesh.component.materials.constSlice()) |material| {
            self.tryLoadMaterial(temp_allocator, material);
        }
    }
}

pub fn tryLoadMesh(self: *Self, allocator: std.mem.Allocator, handle: MeshAsset.Registry.Handle) void {
    if (!self.static_mesh_map.contains(handle)) {
        if (global.assets.meshes.loadAsset(allocator, handle)) |mesh| {
            defer mesh.deinit(allocator);
            const gpu_mesh = Mesh.init(self.allocator, self.device, &mesh) catch return;
            self.static_mesh_map.put(handle, gpu_mesh) catch |err| {
                gpu_mesh.deinit();
                std.log.err("Failed to append static mesh to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load static mesh {}", .{err});
        }
    }
}

pub fn tryLoadTexture(self: *Self, allocator: std.mem.Allocator, handle: Texture2dAsset.Registry.Handle) void {
    _ = self; // autofix
    _ = handle; // autofix
    _ = allocator; // autofix
    // if (!self.texture_map.contains(handle)) {
    //     if (global.assets.textures.loadAsset(allocator, handle)) |texture| {
    //         defer texture.deinit(allocator);

    //         const gpu_texture = Texture.init_2d(self.gpu_device.handle, &texture);
    //         self.texture_map.put(handle, gpu_texture) catch |err| {
    //             gpu_texture.deinit();
    //             std.log.err("Failed to append texture to list {}", .{err});
    //         };
    //     } else |err| {
    //         std.log.err("Failed to load texture {}", .{err});
    //     }
    // }
}

pub fn tryLoadMaterial(self: *Self, allocator: std.mem.Allocator, handle: MaterialAsset.Registry.Handle) void {
    if (!self.material_map.contains(handle)) {
        //Need to load the asset using the non temp allocator, otherwise the name will be invalid
        if (global.assets.materials.loadAsset(self.allocator, handle)) |material| {
            if (material.base_color_texture) |texture_handle|
                self.tryLoadTexture(allocator, texture_handle);

            if (material.metallic_roughness_texture) |texture_handle|
                self.tryLoadTexture(allocator, texture_handle);

            if (material.emissive_texture) |texture_handle|
                self.tryLoadTexture(allocator, texture_handle);

            if (material.occlusion_texture) |texture_handle|
                self.tryLoadTexture(allocator, texture_handle);

            if (material.normal_texture) |texture_handle|
                self.tryLoadTexture(allocator, texture_handle);

            self.material_map.put(handle, material) catch |err| {
                std.log.err("Failed to append material to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load material {}", .{err});
        }
    }
}
