const std = @import("std");
const za = @import("zalgebra");
const global = @import("../../global.zig");

const Transform = @import("../../transform.zig");
const Camera = @import("../camera.zig").Camera;
const RenderScene = @import("../scene.zig").RenderScene;

const Settings = @import("../../rendering/settings.zig");

const MeshAsset = @import("../../asset/mesh.zig");
const Texture2dAsset = @import("../../asset/texture_2d.zig");
const MaterialAsset = @import("../../asset/material.zig");

const ShaderAsset = @import("../../asset/shader.zig");
const ShaderAssetHandle = ShaderAsset.Registry.Handle;

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
});

const Mesh = @import("mesh.zig");
const Texture = @import("texture.zig");

pub const WindowHandle = *anyopaque;

pub const Renderer = struct {
    const Self = @This();

    gpu_device: *c.SDL_GPUDevice,
    window: *c.SDL_Window,

    depth_format: c.SDL_GPUTextureFormat,

    mesh_graphics_pipeline: *c.SDL_GPUGraphicsPipeline,

    static_mesh_map: std.AutoHashMap(MeshAsset.Registry.Handle, Mesh),

    texture_map: std.AutoHashMap(Texture2dAsset.Registry.Handle, Texture),
    material_map: std.AutoHashMap(MaterialAsset.Registry.Handle, MaterialAsset),

    pub fn init(allocator: std.mem.Allocator, settings: Settings.RenderSettings) !Self {
        std.debug.assert(c.SDL_Init(c.SDL_INIT_VIDEO));
        const gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, null).?;

        const driver_name: [*c]const u8 = c.SDL_GetGPUDeviceDriver(gpu_device);

        const device_shader_formats = c.SDL_GetGPUShaderFormats(gpu_device);

        std.log.info("SDL_GPU Context:\n\tBackend: {s}\n\tShader: {}", .{
            driver_name,
            device_shader_formats,
        });

        var depth_format: c.SDL_GPUTextureFormat = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
        if (c.SDL_GPUTextureSupportsFormat(gpu_device, c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT, c.SDL_GPU_TEXTURETYPE_2D, c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) {
            depth_format = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
        } else if (c.SDL_GPUTextureSupportsFormat(gpu_device, c.SDL_GPU_TEXTUREFORMAT_D24_UNORM, c.SDL_GPU_TEXTURETYPE_2D, c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) {
            depth_format = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM;
        }

        const window = createWindow(gpu_device, settings.window_name, settings.size, settings.vsync);

        const vertex_shader = try loadGraphicsShader(allocator, gpu_device, ShaderAssetHandle.fromRepoPath("engine:shaders/test.vert.shader").?);
        defer c.SDL_ReleaseGPUShader(gpu_device, vertex_shader);

        const fragment_shader = try loadGraphicsShader(allocator, gpu_device, ShaderAssetHandle.fromRepoPath("engine:shaders/test.frag.shader").?);
        defer c.SDL_ReleaseGPUShader(gpu_device, fragment_shader);

        const mesh_graphics_pipeline = try loadGraphicsPipeline(
            gpu_device,
            vertex_shader,
            fragment_shader,
            c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window),
            depth_format,
            .{
                .compare_op = c.SDL_GPU_COMPAREOP_LESS,
                .depth_test = true,
                .depth_write = true,
            },
        );

        const static_mesh_map = std.AutoHashMap(MeshAsset.Registry.Handle, Mesh).init(allocator);
        const texture_map = std.AutoHashMap(Texture2dAsset.Registry.Handle, Texture).init(allocator);
        const material_map = std.AutoHashMap(MaterialAsset.Registry.Handle, MaterialAsset).init(allocator);

        return .{
            .gpu_device = gpu_device,
            .window = window,
            .depth_format = depth_format,
            .mesh_graphics_pipeline = mesh_graphics_pipeline,
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

        self.material_map.deinit();

        c.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device, self.mesh_graphics_pipeline);

        destroyWindow(self.gpu_device, self.window);
        c.SDL_DestroyGPUDevice(self.gpu_device);
    }

    pub fn renderScene(self: *Self, temp_allocator: std.mem.Allocator, target: ?WindowHandle, scene: *const RenderScene, camera: struct {
        transform: Transform,
        camera: Camera,
    }) void {
        _ = target; // autofix
        _ = camera; // autofix
        const window: *c.SDL_Window = @ptrCast(self.window);

        const command_buffer = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
        defer _ = c.SDL_SubmitGPUCommandBuffer(command_buffer);

        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        var swapchain_size: [2]u32 = undefined;
        _ = c.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, &swapchain_size[0], &swapchain_size[1]);

        const create_info = c.SDL_GPUTextureCreateInfo{
            .type = c.SDL_GPU_TEXTURETYPE_2D,
            .format = self.depth_format,
            .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
            .width = swapchain_size[0],
            .height = swapchain_size[1],
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        };
        const depth_texture: *c.SDL_GPUTexture = c.SDL_CreateGPUTexture(self.gpu_device, &create_info).?;
        defer c.SDL_ReleaseGPUTexture(self.gpu_device, depth_texture);

        const color_target: c.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_texture,
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

        for (scene.static_meshes.items, 0..) |static_mesh, i| {
            _ = i; // autofix
            if (static_mesh.component.visable == false) {
                continue;
            }

            self.tryLoadMesh(temp_allocator, static_mesh.component.mesh);
            self.tryLoadMaterial(temp_allocator, static_mesh.component.material);
        }

        defer c.SDL_EndGPURenderPass(render_pass);
    }

    pub fn tryLoadMesh(self: *Self, allocator: std.mem.Allocator, handle: MeshAsset.Registry.Handle) void {
        if (!self.static_mesh_map.contains(handle)) {
            if (global.assets.meshes.loadAsset(allocator, handle)) |mesh| {
                defer mesh.deinit(allocator);
                const gpu_mesh = Mesh.init(self.gpu_device, &mesh);
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

                const gpu_texture = Texture.init_2d(self.gpu_device, &texture);
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
            if (global.assets.materials.loadAsset(allocator, handle)) |material| {
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
            .pitch = @sizeOf(MeshAsset.VertexPositions),
        },
        .{
            .slot = 1,
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(MeshAsset.VertexAttributes),
        },
    };
    const vertex_attributes: []const c.SDL_GPUVertexAttribute = &.{
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 0,
            .offset = 0,
        },
        .{
            .buffer_slot = 1,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 1,
            .offset = @offsetOf(MeshAsset.VertexAttributes, "normal"),
        },
        .{
            .buffer_slot = 1,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
            .location = 2,
            .offset = @offsetOf(MeshAsset.VertexAttributes, "tangent"),
        },
        .{
            .buffer_slot = 1,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .location = 3,
            .offset = @offsetOf(MeshAsset.VertexAttributes, "uv0"),
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

pub fn createWindow(gpu_device: *c.SDL_GPUDevice, name: [:0]const u8, size: Settings.WindowSize, vsync: Settings.VerticalSync) *c.SDL_Window {
    var window_width: i32 = 0;
    var window_height: i32 = 0;
    var window_flags = c.SDL_WINDOW_RESIZABLE;

    switch (size) {
        .windowed => |window_size| {
            window_width = window_size[0];
            window_height = window_size[1];
        },
        .maximized => window_flags |= c.SDL_WINDOW_MAXIMIZED,
        .fullscreen => window_flags |= c.SDL_WINDOW_FULLSCREEN,
    }

    const window = c.SDL_CreateWindow(name, window_width, window_height, window_flags).?;
    std.debug.assert(c.SDL_ClaimWindowForGPUDevice(gpu_device, window));

    const present_mode: c.SDL_GPUPresentMode = switch (vsync) {
        .on => c.SDL_GPU_PRESENTMODE_VSYNC,
        .off => c.SDL_GPU_PRESENTMODE_IMMEDIATE,
    };
    std.debug.assert(c.SDL_SetGPUSwapchainParameters(gpu_device, window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, present_mode));

    return @ptrCast(window);
}

pub fn destroyWindow(gpu_device: *c.SDL_GPUDevice, handle: *c.SDL_Window) void {
    const window: *c.SDL_Window = @ptrCast(handle);
    c.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);
    c.SDL_DestroyWindow(window);
}
