const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;
const culling = @import("culling.zig");
const RenderScene = @import("scene.zig").RenderScene;
const Resources = @import("resources.zig");
const Device = @import("vulkan/device.zig");
const Image = @import("vulkan/image.zig");
const Mesh = @import("vulkan/mesh.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");
const utils = @import("vulkan/utils.zig");

pub const BuildCommandBufferData = struct {
    self: *Self,
    resources: *const Resources,
    static_mesh_buffer: Device.BufferHandle,
    material_buffer: Device.BufferHandle,
    model_matrix_buffer_handle: rg.RenderGraphBufferHandle,
    scene: *const RenderScene,
    camera: Camera,
    camera_transform: Transform,
};

const Self = @This();

allocator: std.mem.Allocator,
device: *Device,

opaque_mesh_pipeline: vk.Pipeline,
alpha_cutoff_mesh_pipeline: vk.Pipeline,

opaque_mesh_pipeline_new: vk.Pipeline,

//Debug Values
enable_culling: bool = true,
total_primitives: usize = 0,
rendered_primitives: usize = 0,
culled_primitives: usize = 0,

storage_loads: bool = true,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    device: *Device,
    color_format: vk.Format,
    depth_format: vk.Format,
    pipeline_layout: vk.PipelineLayout,
) !Self {
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
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(MeshAsset.Vertex, "position"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(MeshAsset.Vertex, "normal"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32b32a32_sfloat,
            .offset = @offsetOf(MeshAsset.Vertex, "tangent"),
        },
        .{
            .binding = 0,
            .location = 3,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(MeshAsset.Vertex, "uv0"),
        },
        .{
            .binding = 0,
            .location = 4,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(MeshAsset.Vertex, "uv1"),
        },
    };

    const vertex_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/static_mesh.vert.asset"));
    defer device.device.proxy.destroyShaderModule(vertex_shader, null);

    const vertex_shader_new = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/static_mesh_new.vert.asset"));
    defer device.device.proxy.destroyShaderModule(vertex_shader_new, null);

    const opaque_fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/opaque.frag.asset"));
    defer device.device.proxy.destroyShaderModule(opaque_fragment_shader, null);

    const alpha_cutoff_fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/alpha_cutoff.frag.asset"));
    defer device.device.proxy.destroyShaderModule(alpha_cutoff_fragment_shader, null);

    const opaque_mesh_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        .{
            .color_format = color_format,
            .depth_format = depth_format,
            .cull_mode = .{ .back_bit = true },
        },
        .{ .bindings = &bindings, .attributes = &attributes },
        vertex_shader,
        opaque_fragment_shader,
    );

    const opaque_mesh_pipeline_new = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        .{
            .color_format = color_format,
            .depth_format = depth_format,
            .cull_mode = .{ .back_bit = true },
        },
        .{},
        vertex_shader_new,
        opaque_fragment_shader,
    );

    const alpha_cutoff_mesh_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        .{
            .color_format = color_format,
            .depth_format = depth_format,
            .cull_mode = .{ .back_bit = true },
        },
        .{ .bindings = &bindings, .attributes = &attributes },
        vertex_shader,
        alpha_cutoff_fragment_shader,
    );

    return .{
        .allocator = allocator,
        .device = device,
        .opaque_mesh_pipeline = opaque_mesh_pipeline,
        .alpha_cutoff_mesh_pipeline = alpha_cutoff_mesh_pipeline,
        .opaque_mesh_pipeline_new = opaque_mesh_pipeline_new,
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.opaque_mesh_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.alpha_cutoff_mesh_pipeline, null);

    self.device.device.proxy.destroyPipeline(self.opaque_mesh_pipeline_new, null);
}

pub fn createRenderPass(
    self: *Self,
    temp_allocator: std.mem.Allocator,
    color_target: rg.RenderGraphTextureHandle,
    depth_target: rg.RenderGraphTextureHandle,
    resources: *const Resources,
    scene: *const RenderScene,
    camera: Camera,
    camera_transform: Transform,
    render_graph: *rg.RenderGraph,
) !void {
    const model_matrix_slice = try temp_allocator.alloc(zm.Mat, scene.static_meshes.items.len);
    for (model_matrix_slice, scene.static_meshes.items) |*model_matirx, static_mesh| {
        model_matirx.* = static_mesh.transform.getModelMatrix();
    }
    const model_matrix_buffer = try render_graph.uploadSliceToBuffer(zm.Mat, model_matrix_slice);

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

    const scene_build_data = try temp_allocator.create(BuildCommandBufferData);
    scene_build_data.* = .{
        .self = self,
        .resources = resources,
        .static_mesh_buffer = resources.static_mesh_buffer.?,
        .material_buffer = resources.material_buffer.?,
        .model_matrix_buffer_handle = model_matrix_buffer,
        .scene = scene,
        .camera = camera,
        .camera_transform = camera_transform,
    };
    render_pass.addBuildFn(buildCommandBuffer, scene_build_data);

    try render_graph.render_passes.append(render_graph.allocator, render_pass);
}

pub fn buildCommandBuffer(build_data: ?*anyopaque, device: *Device, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    const data: *BuildCommandBufferData = @ptrCast(@alignCast(build_data.?));
    const self = data.self;

    //Clear stats
    self.total_primitives = 0;
    self.rendered_primitives = 0;
    self.culled_primitives = 0;

    const static_mesh_buffer = device.buffers.get(data.static_mesh_buffer).?;
    const material_buffer = device.buffers.get(data.material_buffer).?;
    const model_matrix_buffer = resources.buffers[data.model_matrix_buffer_handle.index];

    const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
    const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
    const aspect_ratio: f32 = width_float / height_float;
    const view_matrix = data.camera_transform.getViewMatrix();
    var projection_matrix = data.camera.getProjectionMatrix(aspect_ratio);
    projection_matrix[1][1] *= -1.0;
    const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

    const frustum: culling.Frustum = data.camera.getFrustum(aspect_ratio, data.camera_transform);

    for (data.scene.static_meshes.items, 0..) |static_mesh, instance_id| {
        if (static_mesh.component.visable == false) {
            continue;
        }

        if (data.resources.static_mesh_map.get(static_mesh.component.mesh)) |entry| {
            const materials = static_mesh.component.materials.constSlice();
            for (entry.mesh.primitives, materials, 0..) |primitive, material, primitive_index| {
                self.total_primitives += 1;
                if (self.enable_culling) {
                    if (!frustum.intersects(culling.Sphere, .initWorld(primitive.sphere_pos_radius, &static_mesh.transform))) {
                        self.culled_primitives += 1;
                        continue;
                    }
                }
                self.rendered_primitives += 1;

                const PushData = extern struct {
                    view_projection_matrix: zm.Mat,
                    model_matrix_binding: u32,
                    static_mesh_binding: u32,
                    material_binding: u32,
                    mesh_index: u32,
                    primitive_index: u32,
                    material_index: u32,
                };

                if (data.resources.material_map.get(material)) |mat_entry| {
                    command_buffer.bindPipeline(.graphics, switch (mat_entry.material.alpha_mode) {
                        .alpha_opaque => if (!self.storage_loads) self.opaque_mesh_pipeline else self.opaque_mesh_pipeline_new,
                        .alpha_mask => continue,
                        .alpha_blend => continue, //TODO: this
                    });

                    const push_data = PushData{
                        .view_projection_matrix = view_projection_matrix,
                        .model_matrix_binding = model_matrix_buffer.storage_binding.?,
                        .static_mesh_binding = static_mesh_buffer.storage_binding.?.index,
                        .material_binding = material_buffer.storage_binding.?.index,
                        .mesh_index = entry.buffer_index.?,
                        .primitive_index = @intCast(primitive_index),
                        .material_index = mat_entry.buffer_index.?,
                    };
                    command_buffer.pushConstants(device.bindless_layout, .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true }, 0, @sizeOf(PushData), &push_data);

                    //Draw Primitive

                    if (self.storage_loads) {
                        command_buffer.draw(primitive.index_count, 1, 0, @intCast(instance_id));
                    } else {
                        const vertex_buffer = device.buffers.get(entry.mesh.vertex_buffer) orelse continue;
                        const vertex_buffers = [_]vk.Buffer{vertex_buffer.handle};
                        const vertex_offsets = [_]vk.DeviceSize{0};
                        command_buffer.bindVertexBuffers(0, 1, &vertex_buffers, &vertex_offsets);

                        const index_buffer = device.buffers.get(entry.mesh.index_buffer) orelse return;
                        command_buffer.bindIndexBuffer(index_buffer.handle, 0, .uint32);

                        command_buffer.drawIndexed(primitive.index_count, 1, primitive.index_offset, @intCast(primitive.vertex_offset), @intCast(instance_id));
                    }
                }
            }
        }
    }
}

pub fn buildCommandBufferMeshShading(build_data: ?*anyopaque, device: *Device, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    const data: *BuildCommandBufferData = @ptrCast(@alignCast(build_data.?));
    const self = data.self;

    //Clear stats
    self.total_primitives = 0;
    self.rendered_primitives = 0;
    self.culled_primitives = 0;

    const material_buffer = resources.buffers[data.material_buffer_handle.index];

    const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
    const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
    const aspect_ratio: f32 = width_float / height_float;
    const view_matrix = data.camera_transform.getViewMatrix();
    var projection_matrix = data.camera.getProjectionMatrix(aspect_ratio);
    projection_matrix[1][1] *= -1.0;
    const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

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

    const frustum: culling.Frustum = data.camera.getFrustum(aspect_ratio, data.camera_transform);

    for (data.scene.static_meshes.items) |static_mesh| {
        if (static_mesh.component.visable == false) {
            continue;
        }

        if (data.resources.static_mesh_map.get(static_mesh.component.mesh)) |entry| {
            const model_matrix = static_mesh.transform.getModelMatrix();

            const vertex_buffer = device.buffers.get(entry.mesh.vertex_buffer) orelse continue;
            const vertex_buffers = [_]vk.Buffer{vertex_buffer.handle};
            const vertex_offsets = [_]vk.DeviceSize{0};
            command_buffer.bindVertexBuffers(0, 1, &vertex_buffers, &vertex_offsets);

            const index_buffer = device.buffers.get(entry.mesh.index_buffer) orelse return;
            command_buffer.bindIndexBuffer(index_buffer.handle, 0, .uint32);

            const materials = static_mesh.component.materials.constSlice();
            for (entry.mesh.primitives, materials) |primitive, material| {
                self.total_primitives += 1;
                if (self.enable_culling) {
                    if (!frustum.intersects(culling.Sphere, .initWorld(primitive.sphere_pos_radius, &static_mesh.transform))) {
                        self.culled_primitives += 1;
                        continue;
                    }
                }
                self.rendered_primitives += 1;

                const PushData = extern struct {
                    view_projection_matrix: zm.Mat,
                    model_matrix: zm.Mat,
                    material_binding: u32,
                    material_index: u32,
                };

                if (data.resources.material_map.get(material)) |mat_entry| {
                    command_buffer.bindPipeline(.graphics, switch (mat_entry.material.alpha_mode) {
                        .alpha_opaque => self.opaque_mesh_pipeline,
                        .alpha_mask => self.alpha_cutoff_mesh_pipeline,
                        .alpha_blend => continue, //TODO: this
                    });

                    const push_data = PushData{
                        .view_projection_matrix = view_projection_matrix,
                        .model_matrix = model_matrix,
                        .material_binding = material_buffer.storage_binding.?,
                        .material_index = mat_entry.buffer_index,
                    };
                    command_buffer.pushConstants(device.bindless_layout, .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true }, 0, @sizeOf(PushData), &push_data);

                    //Draw Primitive
                    command_buffer.drawIndexed(primitive.index_count, 1, primitive.index_offset, @intCast(primitive.vertex_offset), 0);
                }
            }
        }
    }
}
