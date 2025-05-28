const std = @import("std");

const physics = @import("physics");

const c = @import("../../platform/sdl3.zig").c;
const Device = @import("device.zig");
const Window = @import("../../platform/sdl3.zig").Window;

const zm = @import("zmath");

const Transform = @import("../../transform.zig");
const Camera = @import("../camera.zig").Camera;

const DrawMeshData = struct {
    mesh_id: physics.MeshPrimitive,
    model_matrix: zm.Mat,
    color: zm.Vec,
};

const Self = @This();

enabled: bool = false,

device: Device,

color_format: c.SDL_GPUTextureFormat,
depth_format: c.SDL_GPUTextureFormat,

solid_mesh_graphics_pipeline: *c.SDL_GPUGraphicsPipeline,
wireframe_mesh_graphics_pipeline: *c.SDL_GPUGraphicsPipeline,

meshes: std.AutoArrayHashMap(physics.MeshPrimitive, Mesh),

draw_solid_meshs: std.ArrayList(DrawMeshData),
draw_wireframe_meshs: std.ArrayList(DrawMeshData),

pub fn init(
    allocator: std.mem.Allocator,
    device: Device,
    color_format: c.SDL_GPUTextureFormat,
    depth_format: c.SDL_GPUTextureFormat,
) !Self {
    const vertex_shader = try loadGraphicsShader(allocator, device.handle, ShaderAssetHandle.fromRepoPath("engine:shaders/sdl_gpu/physics_mesh.vert.shader").?);
    defer c.SDL_ReleaseGPUShader(device.handle, vertex_shader);

    const fragment_shader = try loadGraphicsShader(allocator, device.handle, ShaderAssetHandle.fromRepoPath("engine:shaders/sdl_gpu/physics_mesh.frag.shader").?);
    defer c.SDL_ReleaseGPUShader(device.handle, fragment_shader);

    const solid_mesh_graphics_pipeline = try createMeshPipeline(device.handle, .{ .color = color_format, .depth = depth_format }, vertex_shader, fragment_shader, false);
    const wireframe_mesh_graphics_pipeline = try createMeshPipeline(device.handle, .{ .color = color_format, .depth = depth_format }, vertex_shader, fragment_shader, true);

    return .{
        .device = device,
        .color_format = color_format,
        .depth_format = depth_format,
        .solid_mesh_graphics_pipeline = solid_mesh_graphics_pipeline,
        .wireframe_mesh_graphics_pipeline = wireframe_mesh_graphics_pipeline,

        .meshes = std.AutoArrayHashMap(physics.MeshPrimitive, Mesh).init(allocator),
        .draw_solid_meshs = std.ArrayList(DrawMeshData).init(allocator),
        .draw_wireframe_meshs = std.ArrayList(DrawMeshData).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.meshes.values()) |mesh| {
        mesh.deinit();
    }
    self.meshes.deinit();
    self.draw_solid_meshs.deinit();
    self.draw_wireframe_meshs.deinit();
    c.SDL_ReleaseGPUGraphicsPipeline(self.device.handle, self.solid_mesh_graphics_pipeline);
    c.SDL_ReleaseGPUGraphicsPipeline(self.device.handle, self.wireframe_mesh_graphics_pipeline);
}

pub fn buildFrame(self: *Self, world: *physics.World, camera_transform: physics.Transform) void {
    self.draw_solid_meshs.clearRetainingCapacity();
    self.draw_wireframe_meshs.clearRetainingCapacity();

    physics.debugRendererBuildFrame(world, camera_transform);
}

pub fn renderFrame(self: *Self, command_buffer: *c.SDL_GPUCommandBuffer, target_hande: ?*c.SDL_GPUTexture, target_size: [2]u32, camera: struct {
    transform: Transform,
    camera: Camera,
}) void {
    if (!self.enabled) return;

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
    const depth_texture: *c.SDL_GPUTexture = c.SDL_CreateGPUTexture(self.device.handle, &create_info).?;
    defer c.SDL_ReleaseGPUTexture(self.device.handle, depth_texture);

    const color_target: c.SDL_GPUColorTargetInfo = .{
        .texture = target_hande,
        .load_op = c.SDL_GPU_LOADOP_LOAD,
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

    const width_float: f32 = @floatFromInt(target_size[0]);
    const height_float: f32 = @floatFromInt(target_size[1]);
    const aspect_ratio: f32 = width_float / height_float;
    const view_matrix = camera.transform.getViewMatrix();
    const projection_matrix = camera.camera.getProjectionMatrix(aspect_ratio);
    const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

    if (self.draw_solid_meshs.items.len != 0) {
        drawMeshes(&self.meshes, command_buffer, render_pass.?, self.solid_mesh_graphics_pipeline, &view_projection_matrix, self.draw_solid_meshs.items);
    }

    if (self.draw_wireframe_meshs.items.len != 0) {
        drawMeshes(&self.meshes, command_buffer, render_pass.?, self.wireframe_mesh_graphics_pipeline, &view_projection_matrix, self.draw_wireframe_meshs.items);
    }
}

fn drawMeshes(
    mesh_map: *std.AutoArrayHashMap(physics.MeshPrimitive, Mesh),
    command_buffer: *c.SDL_GPUCommandBuffer,
    render_pass: *c.SDL_GPURenderPass,
    pipeline: *c.SDL_GPUGraphicsPipeline,
    view_projection_matrix: *const zm.Mat,
    draw_list: []DrawMeshData,
) void {
    c.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
    c.SDL_PushGPUVertexUniformData(command_buffer, 0, view_projection_matrix, @intCast(@sizeOf(zm.Mat)));

    for (draw_list) |draw_mesh| {
        if (mesh_map.get(draw_mesh.mesh_id)) |mesh| {
            c.SDL_PushGPUVertexUniformData(command_buffer, 1, &draw_mesh.model_matrix, @intCast(@sizeOf(zm.Mat)));
            c.SDL_PushGPUFragmentUniformData(command_buffer, 0, &draw_mesh.color, @intCast(@sizeOf(zm.Vec)));

            const vertex_bindings: []const c.SDL_GPUBufferBinding = &.{
                .{ .buffer = mesh.vetex_buffer, .offset = 0 },
            };
            c.SDL_BindGPUVertexBuffers(render_pass, 0, vertex_bindings.ptr, @intCast(vertex_bindings.len));

            if (mesh.index_buffer) |index_buffer| {
                c.SDL_BindGPUIndexBuffer(render_pass, &.{ .buffer = index_buffer, .offset = 0 }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
                c.SDL_DrawGPUIndexedPrimitives(render_pass, mesh.index_count, 1, 0, 0, 0);
            } else {
                c.SDL_DrawGPUPrimitives(render_pass, mesh.vertex_count, 1, 0, 0);
            }
        }
    }
}

pub fn getDebugRendererData(self: *Self) physics.DebugRendererCallbacks {
    return .{
        .ptr = self,
        .draw_line = drawLineCallback,
        .draw_triangle = drawTriangleCallback,
        .draw_text = drawText3DCallback,
        .create_triangle_mesh = createTriangleMeshCallback,
        .create_indexed_mesh = createIndexedMeshCallback,
        .draw_geometry = drawGeometryCallback,
        .free_mesh = freeMeshPrimitive,
    };
}

fn drawLineCallback(ptr: ?*anyopaque, data: physics.DrawLineData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    //TODO: implement this
}

fn drawTriangleCallback(ptr: ?*anyopaque, data: physics.DrawTriangleData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    //TODO: implement this
}

fn drawText3DCallback(ptr: ?*anyopaque, data: physics.DrawTextData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    //TODO: implement this
}

fn createTriangleMeshCallback(ptr: ?*anyopaque, id: physics.MeshPrimitive, triangles: [*c]const physics.Triangle, triangle_count: usize) callconv(.C) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr));
    const mesh = Mesh.initTriangles(self.device.handle, triangles[0..triangle_count]);
    self.meshes.put(id, mesh) catch |err| std.debug.panic("Failed to put mesh into map: {}", .{err});
}

fn createIndexedMeshCallback(ptr: ?*anyopaque, id: physics.MeshPrimitive, verties: [*c]const physics.Vertex, vertex_count: usize, indices: [*c]const u32, index_count: usize) callconv(.C) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr));
    const mesh = Mesh.initIndexed(self.device.handle, verties[0..vertex_count], indices[0..index_count]);
    self.meshes.put(id, mesh) catch |err| std.debug.panic("Failed to put mesh into map: {}", .{err});
}

fn drawGeometryCallback(ptr: ?*anyopaque, data: physics.DrawGeometryData) callconv(.C) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr));

    const color = zm.f32x4(@floatFromInt(data.color.r), @floatFromInt(data.color.g), @floatFromInt(data.color.b), @floatFromInt(data.color.a)) / zm.splat(zm.Vec, 255.0);
    const model_matrix = zm.matFromArr(data.model_matrix);
    const draw_data: DrawMeshData = .{
        .color = color,
        .mesh_id = data.mesh,
        .model_matrix = model_matrix,
    };

    const DrawModeSolid: u32 = @intFromEnum(physics.DrawMode.solid);
    if (data.draw_mode == DrawModeSolid) {
        self.draw_solid_meshs.append(draw_data) catch |err| std.debug.panic("Failed to append to draw list: {}", .{err});
    } else {
        self.draw_wireframe_meshs.append(draw_data) catch |err| std.debug.panic("Failed to append to draw list: {}", .{err});
    }
}

fn freeMeshPrimitive(ptr: ?*anyopaque, id: physics.MeshPrimitive) callconv(.C) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (self.meshes.fetchSwapRemove(id)) |entry| {
        entry.value.deinit();
    }
}

const Mesh = struct {
    device: *c.SDL_GPUDevice,
    vetex_buffer: *c.SDL_GPUBuffer,
    index_buffer: ?*c.SDL_GPUBuffer,

    vertex_count: u32,
    index_count: u32,

    pub fn initTriangles(device: *c.SDL_GPUDevice, triangles: []const physics.Triangle) Mesh {
        const vetex_buffer = createBufferFromSlice(device, physics.Triangle, triangles, c.SDL_GPU_BUFFERUSAGE_VERTEX);
        return .{
            .device = device,

            .vetex_buffer = vetex_buffer,
            .index_buffer = null,

            .vertex_count = @intCast(triangles.len * 3),
            .index_count = 0,
        };
    }

    pub fn initIndexed(device: *c.SDL_GPUDevice, vertices: []const physics.Vertex, indices: []const u32) Mesh {
        const vetex_buffer = createBufferFromSlice(device, physics.Vertex, vertices, c.SDL_GPU_BUFFERUSAGE_VERTEX);
        const index_buffer = createBufferFromSlice(device, u32, indices, c.SDL_GPU_BUFFERUSAGE_INDEX);
        return .{
            .device = device,

            .vetex_buffer = vetex_buffer,
            .index_buffer = index_buffer,

            .vertex_count = @intCast(vertices.len),
            .index_count = @intCast(indices.len),
        };
    }

    pub fn deinit(self: Mesh) void {
        c.SDL_ReleaseGPUBuffer(self.device, self.vetex_buffer);
        c.SDL_ReleaseGPUBuffer(self.device, self.index_buffer);
    }

    //TODO: don't upload during creation
    fn createBufferFromSlice(device: *c.SDL_GPUDevice, comptime T: type, slice: []const T, usage: c.SDL_GPUBufferUsageFlags) *c.SDL_GPUBuffer {
        const buffer_size: u32 = @intCast(slice.len * @sizeOf(T));
        const buffer = c.SDL_CreateGPUBuffer(device, &.{
            .usage = usage,
            .size = buffer_size,
        }).?;
        const upload_buffer = c.SDL_CreateGPUTransferBuffer(device, &.{
            .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = buffer_size,
        }).?;
        defer c.SDL_ReleaseGPUTransferBuffer(device, upload_buffer);

        const mapped_ptr: [*]T = @alignCast(@ptrCast(c.SDL_MapGPUTransferBuffer(device, upload_buffer, false)));
        const mapped_slice: []T = mapped_ptr[0..slice.len];
        @memcpy(mapped_slice, slice);
        c.SDL_UnmapGPUTransferBuffer(device, upload_buffer);

        const command_buffer = c.SDL_AcquireGPUCommandBuffer(device);
        defer _ = c.SDL_SubmitGPUCommandBuffer(command_buffer);

        const copy_pass = c.SDL_BeginGPUCopyPass(command_buffer);
        defer c.SDL_EndGPUCopyPass(copy_pass);

        c.SDL_UploadToGPUBuffer(copy_pass, &.{
            .offset = 0,
            .transfer_buffer = upload_buffer,
        }, &.{
            .buffer = buffer,
            .offset = 0,
            .size = buffer_size,
        }, false);

        return buffer;
    }
};

const global = @import("../../global.zig");
const ShaderAsset = @import("../../asset/shader.zig");
const ShaderAssetHandle = ShaderAsset.Registry.Handle;
fn loadGraphicsShader(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, handle: ShaderAssetHandle) !*c.SDL_GPUShader {
    var shader = try global.assets.shaders.loadAsset(allocator, handle);
    defer shader.deinit(allocator);

    const create_info = c.SDL_GPUShaderCreateInfo{
        .code = @ptrCast(shader.spirv_code.ptr),
        .code_size = shader.spirv_code.len * @sizeOf(u32),
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

fn createMeshPipeline(
    device: *c.SDL_GPUDevice,
    formats: struct {
        color: c.SDL_GPUTextureFormat,
        depth: c.SDL_GPUTextureFormat,
    },
    vertex_shader: ?*c.SDL_GPUShader,
    fragment_shader: ?*c.SDL_GPUShader,
    wireframe: bool,
) !*c.SDL_GPUGraphicsPipeline {
    _ = wireframe; // autofix

    const vertex_buffers: []const c.SDL_GPUVertexBufferDescription = &.{
        .{
            .slot = 0,
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(physics.Vertex),
        },
    };
    const vertex_attributes: []const c.SDL_GPUVertexAttribute = &.{
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 0,
            .offset = @offsetOf(physics.Vertex, "position"),
        },
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 1,
            .offset = @offsetOf(physics.Vertex, "normal"),
        },
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .location = 2,
            .offset = @offsetOf(physics.Vertex, "uv"),
        },
        .{
            .buffer_slot = 0,
            .format = c.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM,
            .location = 3,
            .offset = @offsetOf(physics.Vertex, "color"),
        },
    };

    var color_targets = try std.BoundedArray(c.SDL_GPUColorTargetDescription, 8).init(0);
    color_targets.appendAssumeCapacity(.{
        .format = formats.color,
    });
    const target_info: c.SDL_GPUGraphicsPipelineTargetInfo = .{
        .num_color_targets = @intCast(color_targets.slice().len),
        .color_target_descriptions = @ptrCast(color_targets.slice().ptr),
        .depth_stencil_format = formats.depth,
        .has_depth_stencil_target = true,
    };

    const depth_stencil_state: c.SDL_GPUDepthStencilState = .{
        .compare_op = c.SDL_GPU_COMPAREOP_LESS,
        .enable_depth_test = true,
        .enable_depth_write = true,
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
        .rasterizer_state = .{
            .cull_mode = c.SDL_GPU_CULLMODE_NONE,
            .fill_mode = c.SDL_GPU_FILLMODE_LINE,
        },
        .multisample_state = .{},
        .depth_stencil_state = depth_stencil_state,
        .target_info = target_info,
    };

    return c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse error.failedToCreateGraphicsPipeline;
}
