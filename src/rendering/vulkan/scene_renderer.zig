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
const Backend = @import("backend.zig");
const Image = @import("image.zig");
const Mesh = @import("mesh.zig");
const Pipeline = @import("pipeline.zig");

pub const BuildCommandBufferData = struct {
    self: *const Self,
    scene: *const RenderScene,
    camera: Camera,
    camera_transform: Transform,
};

const Self = @This();

allocator: std.mem.Allocator,
backend: *Backend,

mesh_pipeline: vk.Pipeline,

static_mesh_map: std.AutoArrayHashMap(MeshAsset.Registry.Handle, Mesh),
texture_map: std.AutoArrayHashMap(Texture2dAsset.Registry.Handle, Backend.ImageHandle),
material_map: std.AutoArrayHashMap(MaterialAsset.Registry.Handle, MaterialAsset),

pub fn init(allocator: std.mem.Allocator, backend: *Backend, color_format: vk.Format, depth_format: vk.Format, pipeline_layout: vk.PipelineLayout) !Self {
    const vertex_shader = try loadGraphicsShader(allocator, backend.device.device, ShaderAssetHandle.fromRepoPath("engine:shaders/vulkan/static_mesh.vert.shader").?);
    defer backend.device.device.destroyShaderModule(vertex_shader, null);

    const opaque_fragment_shader = try loadGraphicsShader(allocator, backend.device.device, ShaderAssetHandle.fromRepoPath("engine:shaders/vulkan/opaque.frag.shader").?);
    defer backend.device.device.destroyShaderModule(opaque_fragment_shader, null);

    const mesh_pipeline = try Pipeline.createGraphicsPipeline(
        allocator,
        backend.device.device,
        pipeline_layout,
        .{
            .color_format = color_format,
            .depth_format = depth_format,
            .cull_mode = .{},
        },
        vertex_shader,
        opaque_fragment_shader,
    );

    return .{
        .allocator = allocator,
        .backend = backend,
        .mesh_pipeline = mesh_pipeline,
        .static_mesh_map = .init(allocator),
        .texture_map = .init(allocator),
        .material_map = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.static_mesh_map.values()) |mesh| {
        mesh.deinit();
    }
    self.static_mesh_map.deinit();

    for (self.texture_map.values()) |texture| {
        self.backend.destroyImage(texture);
    }
    self.texture_map.deinit();

    for (self.material_map.values()) |material| {
        material.deinit(self.allocator);
    }
    self.material_map.deinit();

    self.backend.device.device.destroyPipeline(self.mesh_pipeline, null);
}

// pub fn buildCommandBuffer(data_ptr: ?*anyopaque, device: vk.DeviceProxy, command_buffer: vk.CommandBufferProxy, layout: vk.PipelineLayout, target_size: vk.Extent2D) void {
//     _ = device; // autofix

//     const data: *BuildCommandBufferData = @ptrCast(@alignCast(data_ptr.?));
//     const self = data.self;

//     const width_float: f32 = @floatFromInt(target_size.width);
//     const height_float: f32 = @floatFromInt(target_size.height);
//     const aspect_ratio: f32 = width_float / height_float;
//     const view_matrix = data.camera_transform.getViewMatrix();
//     var projection_matrix = data.camera.getProjectionMatrix(aspect_ratio);
//     projection_matrix[1][1] *= -1.0;
//     const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

//     command_buffer.bindPipeline(.graphics, self.mesh_pipeline);

//     const viewport = vk.Viewport{
//         .x = 0.0,
//         .y = 0.0,
//         .width = @floatFromInt(target_size.width),
//         .height = @floatFromInt(target_size.height),
//         .min_depth = 0.0,
//         .max_depth = 1.0,
//     };
//     command_buffer.setViewport(0, 1, (&viewport)[0..1]);
//     const scissor = vk.Rect2D{
//         .offset = .{ .x = 0, .y = 0 },
//         .extent = target_size,
//     };
//     command_buffer.setScissor(0, 1, (&scissor)[0..1]);

//     for (data.scene.static_meshes.items) |static_mesh| {
//         if (static_mesh.component.visable == false) {
//             continue;
//         }

//         if (self.static_mesh_map.get(static_mesh.component.mesh)) |mesh| {
//             const model_matrix = static_mesh.transform.getModelMatrix();

//             const materials = static_mesh.component.materials.constSlice();
//             for (mesh.primitives, materials) |primtive, material| {
//                 const PushData = extern struct {
//                     view_projection_matrix: zm.Mat,
//                     model_matrix: zm.Mat,
//                     base_color_factor: zm.Vec,
//                 };

//                 var base_color_factor: zm.Vec = .{ 1.0, 0.27, 0.63, 1.0 };
//                 if (self.material_map.get(material)) |mat| {
//                     base_color_factor = mat.base_color_factor;
//                 }

//                 const push_data = PushData{
//                     .view_projection_matrix = view_projection_matrix,
//                     .model_matrix = model_matrix,
//                     .base_color_factor = base_color_factor,
//                 };

//                 command_buffer.pushConstants(layout, .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true }, 0, @sizeOf(PushData), &push_data);

//                 drawPrimitive(command_buffer, primtive);
//             }
//         }
//     }
// }

// pub fn drawPrimitive(
//     command_buffer: vk.CommandBufferProxy,
//     primitive: anytype, // Your primitive struct
// ) void {
//     const vertex_buffers = [_]vk.Buffer{primitive.vertex_buffer.handle};
//     const vertex_offsets = [_]vk.DeviceSize{0};

//     command_buffer.bindVertexBuffers(0, 1, &vertex_buffers, &vertex_offsets);

//     if (primitive.index_buffer) |index_buffer| {
//         command_buffer.bindIndexBuffer(index_buffer.handle, 0, .uint32);
//         command_buffer.drawIndexed(primitive.index_count, 1, 0, 0, 0);
//     } else {
//         command_buffer.draw(primitive.vertex_count, 1, 0, 0);
//     }
// }

pub fn loadSceneData(self: *Self, temp_allocator: std.mem.Allocator, scene: *const RenderScene) void {
    for (scene.static_meshes.items) |static_mesh| {
        self.tryLoadMesh(temp_allocator, static_mesh.component.mesh);

        for (static_mesh.component.materials.constSlice()) |material| {
            self.tryLoadMaterial(temp_allocator, material);
        }
    }
}

pub fn tryLoadMesh(self: *Self, temp_allocator: std.mem.Allocator, handle: MeshAsset.Registry.Handle) void {
    if (!self.static_mesh_map.contains(handle)) {
        if (global.assets.meshes.loadAsset(temp_allocator, handle)) |mesh| {
            defer mesh.deinit(temp_allocator);
            const gpu_mesh = Mesh.init(self.allocator, self.backend, &mesh) catch return;

            self.static_mesh_map.put(handle, gpu_mesh) catch |err| {
                gpu_mesh.deinit();
                std.log.err("Failed to append static mesh to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load static mesh {}", .{err});
        }
    }
}

pub fn tryLoadTexture(self: *Self, temp_allocator: std.mem.Allocator, handle: Texture2dAsset.Registry.Handle) void {
    if (!self.texture_map.contains(handle)) {
        if (global.assets.textures.loadAsset(temp_allocator, handle)) |texture| {
            defer texture.deinit(temp_allocator);

            const format: vk.Format = switch (texture.format) {
                .r8 => .r8_unorm,
                .rg8 => .r8g8_unorm,
                .rgba8 => .r8g8b8a8_unorm,
            };

            const image = self.backend.createImageWithData(.{ texture.width, texture.height }, format, .{ .transfer_dst_bit = true, .sampled_bit = true }, texture.data) catch return;

            self.texture_map.put(handle, image) catch |err| {
                self.backend.destroyImage(image);
                std.log.err("Failed to append texture to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load texture {}", .{err});
        }
    }
}

pub fn tryLoadMaterial(self: *Self, temp_allocator: std.mem.Allocator, handle: MaterialAsset.Registry.Handle) void {
    if (!self.material_map.contains(handle)) {
        //Need to load the asset using the non temp allocator, otherwise the name will be invalid
        if (global.assets.materials.loadAsset(self.allocator, handle)) |material| {
            if (material.base_color_texture) |texture_handle|
                self.tryLoadTexture(temp_allocator, texture_handle);

            if (material.metallic_roughness_texture) |texture_handle|
                self.tryLoadTexture(temp_allocator, texture_handle);

            if (material.emissive_texture) |texture_handle|
                self.tryLoadTexture(temp_allocator, texture_handle);

            if (material.occlusion_texture) |texture_handle|
                self.tryLoadTexture(temp_allocator, texture_handle);

            if (material.normal_texture) |texture_handle|
                self.tryLoadTexture(temp_allocator, texture_handle);

            self.material_map.put(handle, material) catch |err| {
                std.log.err("Failed to append material to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load material {}", .{err});
        }
    }
}

fn loadGraphicsShader(allocator: std.mem.Allocator, device: vk.DeviceProxy, handle: ShaderAssetHandle) !vk.ShaderModule {
    var shader = try global.assets.shaders.loadAsset(allocator, handle);
    defer shader.deinit(allocator);

    if (shader.target != .vulkan) {
        return error.InvalidShaderTarget;
    }

    return try device.createShaderModule(&.{
        .flags = .{},
        .code_size = shader.spirv_code.len * @sizeOf(u32), //Code size is in bytes, despite the p_code being a u32ptr
        .p_code = @alignCast(@ptrCast(shader.spirv_code.ptr)),
    }, null);
}
