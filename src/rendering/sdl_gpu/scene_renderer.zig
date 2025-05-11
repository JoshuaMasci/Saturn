const std = @import("std");

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
const Texture = @import("texture.zig");

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    gpu_device: Device,

    color_format: c.SDL_GPUTextureFormat,
    depth_format: c.SDL_GPUTextureFormat,

    opaque_mesh_pipeline: *c.SDL_GPUGraphicsPipeline,
    mask_mesh_pipeline: *c.SDL_GPUGraphicsPipeline,

    linear_sampler: *c.SDL_GPUSampler,
    empty_texture: Texture,

    static_mesh_map: std.AutoHashMap(MeshAsset.Registry.Handle, Mesh),
    texture_map: std.AutoHashMap(Texture2dAsset.Registry.Handle, Texture),
    material_map: std.AutoHashMap(MaterialAsset.Registry.Handle, MaterialAsset),

    pub fn init(
        allocator: std.mem.Allocator,
        gpu_device: Device,
        formats: struct {
            color: c.SDL_GPUTextureFormat,
            depth: c.SDL_GPUTextureFormat,
        },
    ) !Self {
        const vertex_shader = try loadGraphicsShader(allocator, gpu_device.handle, ShaderAssetHandle.fromRepoPath("engine:shaders/static_mesh.vert.shader").?);
        defer c.SDL_ReleaseGPUShader(gpu_device.handle, vertex_shader);

        const opaque_fragment_shader = try loadGraphicsShader(allocator, gpu_device.handle, ShaderAssetHandle.fromRepoPath("engine:shaders/opaque.frag.shader").?);
        defer c.SDL_ReleaseGPUShader(gpu_device.handle, opaque_fragment_shader);

        const opaque_mesh_pipeline = try loadGraphicsPipeline(
            gpu_device.handle,
            vertex_shader,
            opaque_fragment_shader,
            formats.color,
            formats.depth,
            .{
                .compare_op = c.SDL_GPU_COMPAREOP_LESS,
                .depth_test = true,
                .depth_write = true,
            },
        );

        const mask_fragment_shader = try loadGraphicsShader(allocator, gpu_device.handle, ShaderAssetHandle.fromRepoPath("engine:shaders/alpha_mask.frag.shader").?);
        defer c.SDL_ReleaseGPUShader(gpu_device.handle, mask_fragment_shader);

        const mask_mesh_pipeline = try loadGraphicsPipeline(
            gpu_device.handle,
            vertex_shader,
            mask_fragment_shader,
            formats.color,
            formats.depth,
            .{
                .compare_op = c.SDL_GPU_COMPAREOP_LESS,
                .depth_test = true,
                .depth_write = true,
            },
        );

        const linear_sampler = c.SDL_CreateGPUSampler(gpu_device.handle, &.{
            .min_filter = c.SDL_GPU_FILTER_LINEAR,
            .mag_filter = c.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
            .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        }).?;

        const empty_asset: Texture2dAsset = .{
            .name = "empty texture",
            .format = .rgba8,
            .width = 2,
            .height = 2,
            .data = &(.{0} ** 16),
        };

        const empty_texture = Texture.init_2d(gpu_device.handle, &empty_asset);

        const static_mesh_map = std.AutoHashMap(MeshAsset.Registry.Handle, Mesh).init(allocator);
        const texture_map = std.AutoHashMap(Texture2dAsset.Registry.Handle, Texture).init(allocator);
        const material_map = std.AutoHashMap(MaterialAsset.Registry.Handle, MaterialAsset).init(allocator);

        return .{
            .allocator = allocator,
            .gpu_device = gpu_device,
            .color_format = formats.color,
            .depth_format = formats.depth,

            .opaque_mesh_pipeline = opaque_mesh_pipeline,
            .mask_mesh_pipeline = mask_mesh_pipeline,

            .linear_sampler = linear_sampler,
            .empty_texture = empty_texture,
            .static_mesh_map = static_mesh_map,
            .texture_map = texture_map,
            .material_map = material_map,
        };
    }

    pub fn deinit(self: *Self) void {
        {
            var iter = self.static_mesh_map.valueIterator();
            while (iter.next()) |mesh| {
                mesh.deinit();
            }
            self.static_mesh_map.deinit();
        }

        {
            var iter = self.texture_map.valueIterator();
            while (iter.next()) |texture| {
                texture.deinit();
            }
            self.texture_map.deinit();
        }

        {
            var iter = self.material_map.valueIterator();
            while (iter.next()) |material| {
                material.deinit(self.allocator);
            }
            self.material_map.deinit();
        }

        c.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device.handle, self.opaque_mesh_pipeline);
        c.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device.handle, self.mask_mesh_pipeline);
        c.SDL_ReleaseGPUSampler(self.gpu_device.handle, self.linear_sampler);
        self.empty_texture.deinit();
    }

    pub fn render(self: *Self, temp_allocator: std.mem.Allocator, command_buffer: *c.SDL_GPUCommandBuffer, target_hande: ?*c.SDL_GPUTexture, target_size: [2]u32, scene: *const RenderScene, camera: struct {
        transform: Transform,
        camera: Camera,
    }) void {
        const create_info = c.SDL_GPUTextureCreateInfo{
            .type = c.SDL_GPU_TEXTURETYPE_2D,
            .format = self.depth_format,
            .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
            .width = target_size[0],
            .height = target_size[1],
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        };
        const depth_texture: *c.SDL_GPUTexture = c.SDL_CreateGPUTexture(self.gpu_device.handle, &create_info).?;
        defer c.SDL_ReleaseGPUTexture(self.gpu_device.handle, depth_texture);

        const color_target: c.SDL_GPUColorTargetInfo = .{
            .texture = target_hande,
            .clear_color = .{ .r = 0.0, .g = 0.75, .b = 0.5, .a = 1.0 },
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };

        const depth_target: c.SDL_GPUDepthStencilTargetInfo = .{
            .texture = depth_texture,
            .clear_depth = 1.0,
            .clear_stencil = 0,
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };

        const render_pass = c.SDL_BeginGPURenderPass(command_buffer, &color_target, 1, &depth_target);
        defer c.SDL_EndGPURenderPass(render_pass);

        //Write ViewProjection Matrix
        {
            const width_float: f32 = @floatFromInt(target_size[0]);
            const height_float: f32 = @floatFromInt(target_size[1]);
            const aspect_ratio: f32 = width_float / height_float;
            const view_matrix = camera.transform.getViewMatrix();
            const projection_matrix = camera.camera.getProjectionMatrix(aspect_ratio); //TODO: this is probably not be the correct matrix for SDL_GPU's clip space
            const view_projection_matrix = zm.mul(view_matrix, projection_matrix);
            c.SDL_PushGPUVertexUniformData(command_buffer, 0, &view_projection_matrix, @intCast(@sizeOf(zm.Mat)));
        }

        for (scene.static_meshes.items) |static_mesh| {
            if (static_mesh.component.visable == false) {
                continue;
            }

            self.tryLoadMesh(temp_allocator, static_mesh.component.mesh);
            if (self.static_mesh_map.get(static_mesh.component.mesh)) |mesh| {
                const model_matrix = static_mesh.transform.getModelMatrix();
                c.SDL_PushGPUVertexUniformData(command_buffer, 1, &model_matrix, @intCast(@sizeOf(zm.Mat)));

                const materials = static_mesh.component.materials.constSlice();
                for (mesh.primitives, materials) |primtive, material| {
                    self.tryLoadMaterial(temp_allocator, material);
                    if (self.bindMaterial(material, command_buffer, render_pass)) {
                        bindAndDispatchPrimitive(render_pass, primtive);
                    }
                }
            }
        }
    }

    fn bindAndDispatchPrimitive(
        render_pass: ?*c.SDL_GPURenderPass,
        primitive: Mesh.Primitive,
    ) void {
        const vertex_bindings: []const c.SDL_GPUBufferBinding = &.{
            .{ .buffer = primitive.vertex_buffer, .offset = 0 },
        };
        c.SDL_BindGPUVertexBuffers(render_pass, 0, vertex_bindings.ptr, @intCast(vertex_bindings.len));

        if (primitive.index_buffer) |index_buffer| {
            c.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = index_buffer, .offset = 0 }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
            c.SDL_DrawGPUIndexedPrimitives(render_pass, primitive.index_count, 1, 0, 0, 0);
        } else {
            c.SDL_DrawGPUPrimitives(render_pass, primitive.vertex_count, 1, 0, 0);
        }
    }

    fn bindMaterial(
        self: *Self,
        handle: MaterialAsset.Registry.Handle,
        command_buffer: ?*c.SDL_GPUCommandBuffer,
        render_pass: ?*c.SDL_GPURenderPass,
    ) bool {
        const material = self.material_map.get(handle) orelse return false;

        switch (material.alpha_mode) {
            .alpha_opaque => c.SDL_BindGPUGraphicsPipeline(render_pass, self.opaque_mesh_pipeline),
            .alpha_mask => c.SDL_BindGPUGraphicsPipeline(render_pass, self.mask_mesh_pipeline),
            .alpha_blend => return false,
        }

        const UniformData = extern struct {
            base_color_factor: [4]f32,
            base_color_texture_enable: i32,
            alpha_cutoff: f32,
        };

        var uniform_data: UniformData = .{
            .base_color_factor = material.base_color_factor,
            .base_color_texture_enable = 0,
            .alpha_cutoff = material.alpha_cutoff,
        };

        if (material.base_color_texture) |texture_handle| {
            uniform_data.base_color_texture_enable = @intFromBool(self.bindTexture(texture_handle, render_pass, 0));
        } else {
            self.bindEmptyTexture(render_pass, 0);
        }

        const uniform_data_bytes: []const u8 = std.mem.sliceAsBytes((&uniform_data)[0..1]);
        c.SDL_PushGPUFragmentUniformData(command_buffer, 0, uniform_data_bytes.ptr, @intCast(uniform_data_bytes.len));

        return true;
    }

    fn bindTexture(
        self: *Self,
        handle: Texture2dAsset.Registry.Handle,
        render_pass: ?*c.SDL_GPURenderPass,
        slot: u32,
    ) bool {
        if (self.texture_map.get(handle)) |texture| {
            const bindings: []const c.SDL_GPUTextureSamplerBinding = &.{.{
                .sampler = self.linear_sampler,
                .texture = texture.handle,
            }};
            c.SDL_BindGPUFragmentSamplers(render_pass, slot, bindings.ptr, @intCast(bindings.len));
            return true;
        } else {
            self.bindEmptyTexture(render_pass, slot);
            return false;
        }
    }

    fn bindEmptyTexture(
        self: *Self,
        render_pass: ?*c.SDL_GPURenderPass,
        slot: u32,
    ) void {
        const bindings: []const c.SDL_GPUTextureSamplerBinding = &.{.{
            .sampler = self.linear_sampler,
            .texture = self.empty_texture.handle,
        }};
        c.SDL_BindGPUFragmentSamplers(render_pass, slot, bindings.ptr, @intCast(bindings.len));
    }

    pub fn tryLoadMesh(self: *Self, allocator: std.mem.Allocator, handle: MeshAsset.Registry.Handle) void {
        if (!self.static_mesh_map.contains(handle)) {
            if (global.assets.meshes.loadAsset(allocator, handle)) |mesh| {
                defer mesh.deinit(allocator);
                const gpu_mesh = Mesh.init(self.allocator, self.gpu_device.handle, &mesh) catch return;
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
        if (!self.texture_map.contains(handle)) {
            if (global.assets.textures.loadAsset(allocator, handle)) |texture| {
                defer texture.deinit(allocator);

                const gpu_texture = Texture.init_2d(self.gpu_device.handle, &texture);
                self.texture_map.put(handle, gpu_texture) catch |err| {
                    gpu_texture.deinit();
                    std.log.err("Failed to append texture to list {}", .{err});
                };
            } else |err| {
                std.log.err("Failed to load texture {}", .{err});
            }
        }
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
};

fn loadGraphicsShader(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, handle: ShaderAssetHandle) !*c.SDL_GPUShader {
    var shader = try global.assets.shaders.loadAsset(allocator, handle);
    defer shader.deinit(allocator);

    const create_info = c.SDL_GPUShaderCreateInfo{
        .code = shader.spirv_code.ptr,
        .code_size = shader.spirv_code.len,
        .entrypoint = "main",
        .format = c.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = switch (shader.stage) {
            .vertex => c.SDL_GPU_SHADERSTAGE_VERTEX,
            .fragment => c.SDL_GPU_SHADERSTAGE_FRAGMENT,
            else => return error.invalidShaderStage,
        },
        .num_samplers = shader.bindings.samplers,
        .num_storage_textures = shader.bindings.storage_textures,
        .num_storage_buffers = shader.bindings.storage_buffers,
        .num_uniform_buffers = shader.bindings.uniform_buffers,
    };

    return c.SDL_CreateGPUShader(device, &create_info) orelse error.failedToCreateShader;
}

fn loadGraphicsPipeline(
    device: *c.SDL_GPUDevice,
    vertex_shader: ?*c.SDL_GPUShader,
    fragment_shader: ?*c.SDL_GPUShader,
    color_target_format_opt: ?c.SDL_GPUTextureFormat,
    depth_target_format: ?c.SDL_GPUTextureFormat,
    depth_state: struct {
        compare_op: c.SDL_GPUCompareOp = c.SDL_GPU_COMPAREOP_INVALID,
        depth_test: bool = false,
        depth_write: bool = false,
    },
) !*c.SDL_GPUGraphicsPipeline {
    const vertex_buffers: []const c.SDL_GPUVertexBufferDescription = &.{
        .{
            .slot = 0,
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(MeshAsset.Vertex),
        },
    };
    const vertex_attributes: []const c.SDL_GPUVertexAttribute = &.{
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 0,
            .offset = @offsetOf(MeshAsset.Vertex, "position"),
        },
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 1,
            .offset = @offsetOf(MeshAsset.Vertex, "normal"),
        },
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
            .location = 2,
            .offset = @offsetOf(MeshAsset.Vertex, "tangent"),
        },
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .location = 3,
            .offset = @offsetOf(MeshAsset.Vertex, "uv0"),
        },
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .location = 4,
            .offset = @offsetOf(MeshAsset.Vertex, "uv1"),
        },
    };

    var color_targets = try std.BoundedArray(c.SDL_GPUColorTargetDescription, 8).init(0);
    if (color_target_format_opt) |color_target_format| {
        color_targets.appendAssumeCapacity(.{
            .format = color_target_format,
        });
    }
    const target_info: c.SDL_GPUGraphicsPipelineTargetInfo = .{
        .num_color_targets = @intCast(color_targets.slice().len),
        .color_target_descriptions = @ptrCast(color_targets.slice().ptr),
        .depth_stencil_format = depth_target_format orelse undefined,
        .has_depth_stencil_target = depth_target_format != null,
    };

    const depth_stencil_state: c.SDL_GPUDepthStencilState = .{
        .compare_op = depth_state.compare_op,
        .enable_depth_test = depth_state.depth_test,
        .enable_depth_write = depth_state.depth_write,
    };

    var create_info = c.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = vertex_buffers.ptr,
            .num_vertex_buffers = vertex_buffers.len,
            .vertex_attributes = vertex_attributes.ptr,
            .num_vertex_attributes = vertex_attributes.len,
        },
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{},
        .multisample_state = .{},
        .depth_stencil_state = depth_stencil_state,
        .target_info = target_info,
    };

    return c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse error.failedToCreateGraphicsPipeline;
}
