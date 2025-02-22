const std = @import("std");
const za = @import("zalgebra");
const global = @import("../../global.zig");

const Transform = @import("../../transform.zig");
const Camera = @import("../camera.zig").Camera;
const RenderScene = @import("../scene.zig").RenderScene;

const Settings = @import("../../rendering/settings.zig");

const Shader = @import("../../asset/shader.zig");
const ShaderAssetHandle = Shader.Registry.Handle;

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
});

pub const WindowHandle = *anyopaque;

pub const Renderer = struct {
    const Self = @This();

    gpu_device: *c.SDL_GPUDevice,
    window: *c.SDL_Window,

    //mesh_shader: *c.SDL_GPUGraphicsPipeline,

    pub fn init(allocator: std.mem.Allocator, settings: Settings.RenderSettings) !Self {
        std.debug.assert(c.SDL_Init(c.SDL_INIT_VIDEO));
        const gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, null).?;

        const driver_name: [*c]const u8 = c.SDL_GetGPUDeviceDriver(gpu_device);

        const device_shader_formats = c.SDL_GetGPUShaderFormats(gpu_device);

        std.log.info("SDL_GPU Context:\n\tBackend: {s}\n\tShader: {}", .{
            driver_name,
            device_shader_formats,
        });

        const vertex_shader = try loadGraphicsShader(allocator, gpu_device, ShaderAssetHandle.fromRepoPath("engine:shaders/test.vert.shader").?);
        defer c.SDL_ReleaseGPUShader(gpu_device, vertex_shader);

        const fragment_shader = try loadGraphicsShader(allocator, gpu_device, ShaderAssetHandle.fromRepoPath("engine:shaders/test.frag.shader").?);
        defer c.SDL_ReleaseGPUShader(gpu_device, fragment_shader);

        const window = createWindow(gpu_device, settings.window_name, settings.size, settings.vsync);

        const mesh_graphics_pipeline = try loadGraphicsPipeline(
            gpu_device,
            vertex_shader,
            fragment_shader,
            c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window),
        );
        defer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, mesh_graphics_pipeline);

        return .{
            .gpu_device = gpu_device,
            .window = window,
        };
    }

    pub fn deinit(self: *Self) void {
        destroyWindow(self.gpu_device, self.window);
        c.SDL_DestroyGPUDevice(self.gpu_device);
    }

    pub fn clearFramebuffer(self: *Self) void {
        _ = self; // autofix

    }

    pub fn renderScene(self: *Self, target: ?WindowHandle, scene: *const RenderScene, camera: struct {
        transform: Transform,
        camera: Camera,
    }) void {
        _ = target; // autofix
        _ = scene; // autofix
        _ = camera; // autofix
        const window: *c.SDL_Window = @ptrCast(self.window);

        const command_buffer = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
        defer _ = c.SDL_SubmitGPUCommandBuffer(command_buffer);

        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        _ = c.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, null, null);

        const color_target: c.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_texture,
            .clear_color = .{ .r = 0.0, .g = 0.75, .b = 0.5, .a = 1.0 },
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };
        const render_pass = c.SDL_BeginGPURenderPass(command_buffer, &color_target, 1, null);
        defer c.SDL_EndGPURenderPass(render_pass);
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

const Mesh = @import("../../asset/mesh.zig");

fn loadGraphicsPipeline(
    device: *c.SDL_GPUDevice,
    vertex_shader: ?*c.SDL_GPUShader,
    fragment_shader: ?*c.SDL_GPUShader,
    target_format: c.SDL_GPUTextureFormat,
) !*c.SDL_GPUGraphicsPipeline {
    const vertex_buffers: []const c.SDL_GPUVertexBufferDescription = &.{
        .{
            .slot = 0,
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(Mesh.VertexPositions),
        },
        .{
            .slot = 1,
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(Mesh.VertexAttributes),
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
            .offset = @offsetOf(Mesh.VertexAttributes, "normal"),
        },
        .{
            .buffer_slot = 1,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
            .location = 2,
            .offset = @offsetOf(Mesh.VertexAttributes, "tangent"),
        },
        .{
            .buffer_slot = 1,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .location = 3,
            .offset = @offsetOf(Mesh.VertexAttributes, "uv0"),
        },
    };

    const color_targets: []const c.SDL_GPUColorTargetDescription = &.{.{
        .format = target_format,
    }};

    const target_info: c.SDL_GPUGraphicsPipelineTargetInfo = .{
        .num_color_targets = @intCast(color_targets.len),
        .color_target_descriptions = @ptrCast(color_targets.ptr),
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
        .depth_stencil_state = .{},
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
