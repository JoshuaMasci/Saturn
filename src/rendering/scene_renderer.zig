const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MaterialAsset = @import("../asset/material.zig");
const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const Texture2dAsset = @import("../asset/texture.zig");
const global = @import("../global.zig");
const c = @import("../platform/sdl3.zig").c;
const Window = @import("../platform/sdl3.zig").Window;
const Settings = @import("../rendering/settings.zig");
const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;
const RenderScene = @import("scene.zig").RenderScene;
const Device = @import("vulkan/device.zig");
const Image = @import("vulkan/image.zig");
const Mesh = @import("vulkan/mesh.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");
const utils = @import("vulkan/utils.zig");
const culling = @import("culling.zig");

pub const BuildCommandBufferData = struct {
    self: *const Self,
    scene: *const RenderScene,
    camera: Camera,
    camera_transform: Transform,
};

const Self = @This();

allocator: std.mem.Allocator,
registry: *const AssetRegistry,
device: *Device,

mesh_pipeline: vk.Pipeline,

static_mesh_map: std.AutoArrayHashMap(AssetRegistry.AssetHandle, Mesh),
texture_map: std.AutoArrayHashMap(AssetRegistry.Handle, Device.ImageHandle),
material_map: std.AutoArrayHashMap(AssetRegistry.Handle, MaterialAsset),

//Debug Values
enable_culling: bool = false,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    device: *Device,
    color_format: vk.Format,
    depth_format: vk.Format,
    pipeline_layout: vk.PipelineLayout,
) !Self {
    const vertex_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/static_mesh.vert.asset"));
    defer device.device.proxy.destroyShaderModule(vertex_shader, null);

    const opaque_fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/opaque.frag.asset"));
    defer device.device.proxy.destroyShaderModule(opaque_fragment_shader, null);

    const bindings = [_]vk.VertexInputBindingDescription{
        .{
            .binding = 0,
            .stride = @sizeOf(MeshAsset.Vertex),
            .input_rate = .vertex,
        },
    };

    const attributes = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat, // FLOAT3
            .offset = @offsetOf(MeshAsset.Vertex, "position"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat, // FLOAT3
            .offset = @offsetOf(MeshAsset.Vertex, "normal"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32b32a32_sfloat, // FLOAT4
            .offset = @offsetOf(MeshAsset.Vertex, "tangent"),
        },
        .{
            .binding = 0,
            .location = 3,
            .format = .r32g32_sfloat, // FLOAT2
            .offset = @offsetOf(MeshAsset.Vertex, "uv0"),
        },
        .{
            .binding = 0,
            .location = 4,
            .format = .r32g32_sfloat, // FLOAT2
            .offset = @offsetOf(MeshAsset.Vertex, "uv1"),
        },
    };

    const mesh_pipeline = try Pipeline.createGraphicsPipeline(
        allocator,
        device.device.proxy,
        pipeline_layout,
        .{
            .color_format = color_format,
            .depth_format = depth_format,
            .cull_mode = .{},
        },
        .{ .bindings = &bindings, .attributes = &attributes },
        vertex_shader,
        opaque_fragment_shader,
    );

    return .{
        .allocator = allocator,
        .registry = registry,
        .device = device,
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
        self.device.destroyImage(texture);
    }
    self.texture_map.deinit();

    for (self.material_map.values()) |material| {
        material.deinit(self.allocator);
    }
    self.material_map.deinit();

    self.device.device.proxy.destroyPipeline(self.mesh_pipeline, null);
}

pub fn createRenderPass(
    self: *Self,
    temp_allocator: std.mem.Allocator,
    color_target: rg.RenderGraphTextureHandle,
    depth_target: rg.RenderGraphTextureHandle,
    scene: *const RenderScene,
    camera: Camera,
    camera_transform: Transform,
    render_graph: *rg.RenderGraph,
) !void {
    var render_pass = try rg.RenderPass.init(temp_allocator, "Scene Pass");
    try render_pass.addColorAttachment(.{
        .texture = color_target,
        .clear = .{ .float_32 = @splat(0.0) },
        .store = true,
    });
    render_pass.addDepthAttachment(.{
        .texture = depth_target,
        .clear = 1.0,
        .store = true,
    });

    self.loadSceneData(self.allocator, scene);

    const scene_build_data = try temp_allocator.create(BuildCommandBufferData);
    scene_build_data.* = .{
        .self = self,
        .camera = camera,
        .camera_transform = camera_transform,
        .scene = scene,
    };
    render_pass.addBuildFn(buildCommandBuffer, scene_build_data);

    try render_graph.render_passes.append(render_pass);
}

pub fn buildCommandBuffer(build_data: ?*anyopaque, device: *Device, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = resources; // autofix

    const data: *BuildCommandBufferData = @ptrCast(@alignCast(build_data.?));
    const self = data.self;

    const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
    const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
    const aspect_ratio: f32 = width_float / height_float;
    const view_matrix = data.camera_transform.getViewMatrix();
    var projection_matrix = data.camera.getProjectionMatrix(aspect_ratio);
    projection_matrix[1][1] *= -1.0;
    const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

    command_buffer.bindPipeline(.graphics, self.mesh_pipeline);

    const viewport = vk.Viewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(raster_pass_extent.?.width),
        .height = @floatFromInt(raster_pass_extent.?.height),
        .min_depth = 0.0,
        .max_depth = 1.0,
    };
    command_buffer.setViewport(0, 1, (&viewport)[0..1]);
    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = raster_pass_extent.?,
    };
    command_buffer.setScissor(0, 1, (&scissor)[0..1]);

    const frustum: culling.Frustum = .fromViewProjectionMatrix(view_projection_matrix);

    for (data.scene.static_meshes.items) |static_mesh| {
        if (static_mesh.component.visable == false) {
            continue;
        }

        if (self.static_mesh_map.get(static_mesh.component.mesh)) |mesh| {
            const model_matrix = static_mesh.transform.getModelMatrix();

            const materials = static_mesh.component.materials.constSlice();
            for (mesh.primitives, materials) |primtive, material| {
                if (self.enable_culling) {
                    if (!frustum.intersects(culling.Sphere, .initWorld(primtive.sphere_pos_radius, &static_mesh.transform))) {
                        continue;
                    }
                }

                const PushData = extern struct {
                    view_projection_matrix: zm.Mat,
                    model_matrix: zm.Mat,
                    base_color_factor: zm.Vec,
                    base_color_texture: u32,
                };

                var base_color_factor: zm.Vec = .{ 1.0, 0.27, 0.63, 1.0 };
                var base_color_texture: u32 = 0;
                if (self.material_map.get(material)) |mat| {
                    base_color_factor = mat.base_color_factor;

                    if (mat.base_color_texture) |handle| {
                        if (self.texture_map.get(handle)) |tex_handle| {
                            if (device.images.get(tex_handle)) |image| {
                                base_color_texture = image.sampled_binding.?;
                            }
                        }
                    }
                }

                const push_data = PushData{
                    .view_projection_matrix = view_projection_matrix,
                    .model_matrix = model_matrix,
                    .base_color_factor = base_color_factor,
                    .base_color_texture = base_color_texture,
                };
                command_buffer.pushConstants(device.bindless_layout, .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true }, 0, @sizeOf(PushData), &push_data);

                drawPrimitive(device, command_buffer, primtive);
            }
        }
    }
}

pub fn drawPrimitive(
    device: *Device,
    command_buffer: vk.CommandBufferProxy,
    primitive: anytype, // Your primitive struct
) void {
    const vertex_buffer = device.buffers.get(primitive.vertex_buffer) orelse return;

    const vertex_buffers = [_]vk.Buffer{vertex_buffer.handle};
    const vertex_offsets = [_]vk.DeviceSize{0};

    command_buffer.bindVertexBuffers(0, 1, &vertex_buffers, &vertex_offsets);

    if (primitive.index_buffer) |index_buffer_handle| {
        const index_buffer = device.buffers.get(index_buffer_handle) orelse return;

        command_buffer.bindIndexBuffer(index_buffer.handle, 0, .uint32);
        command_buffer.drawIndexed(primitive.index_count, 1, 0, 0, 0);
    } else {
        command_buffer.draw(primitive.vertex_count, 1, 0, 0);
    }
}

pub fn loadSceneData(self: *Self, temp_allocator: std.mem.Allocator, scene: *const RenderScene) void {
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

pub fn tryLoadTexture(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) void {
    if (!self.texture_map.contains(handle)) {
        if (self.registry.loadAsset(Texture2dAsset, temp_allocator, handle)) |texture| {
            defer texture.deinit(temp_allocator);

            const format: vk.Format = switch (texture.format) {
                .r8 => .r8_unorm,
                .rg8 => .r8g8_unorm,
                .rgba8 => .r8g8b8a8_unorm,
            };

            const image = self.device.createImageWithData(.{ texture.width, texture.height }, format, .{ .transfer_dst_bit = true, .sampled_bit = true }, texture.data) catch return;

            self.texture_map.put(handle, image) catch |err| {
                self.device.destroyImage(image);
                std.log.err("Failed to append texture to list {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load texture {}", .{err});
        }
    }
}

pub fn tryLoadMaterial(self: *Self, temp_allocator: std.mem.Allocator, handle: AssetRegistry.Handle) void {
    if (!self.material_map.contains(handle)) {
        //Need to load the asset using the non temp allocator, otherwise the name will be invalid
        if (self.registry.loadAsset(MaterialAsset, self.allocator, handle)) |material| {
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
