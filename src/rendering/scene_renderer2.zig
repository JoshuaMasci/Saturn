const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");
const SceneCamera = @import("camera.zig").SceneCamera;
const CullData = @import("culling.zig").CullData;
const RenderScene2 = @import("scene2.zig");
const Resources = @import("resources.zig");
const Backend = @import("vulkan/backend.zig");
const Image = @import("vulkan/image.zig");
const Mesh = @import("vulkan/mesh.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");
const utils = @import("vulkan/utils.zig");
const UnifiedGeometryBuffer = @import("unified_geometry_buffer.zig");

const Self = @This();

allocator: std.mem.Allocator,
device: *Backend,

opaque_draw_pipeline: vk.Pipeline,

//Debug Values
gpu_culling: bool = true,
locked_culling_info: ?SceneCamera = null,

mesh_shading: bool = false,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    device: *Backend,
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

    const opaque_fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/glsl/opaque.frag.asset"));
    defer device.device.proxy.destroyShaderModule(opaque_fragment_shader, null);

    const pipeline_config: Pipeline.PipelineConfig = .{
        .color_format = color_format,
        .depth_format = depth_format,
        .cull_mode = .{ .back_bit = true },
    };

    const draw_mesh_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/glsl/draw_legacy.vert.asset"));
    defer device.device.proxy.destroyShaderModule(draw_mesh_shader, null);
    const opaque_draw_indirect_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        pipeline_config,
        .{
            .bindings = &bindings,
            .attributes = &attributes,
        },
        draw_mesh_shader,
        opaque_fragment_shader,
    );

    return .{
        .allocator = allocator,
        .device = device,
        .opaque_draw_pipeline = opaque_draw_indirect_pipeline,
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.opaque_draw_pipeline, null);
}

pub fn createRenderPass(
    self: *Self,
    temp_allocator: std.mem.Allocator,
    color_target: rg.RenderGraphTextureHandle,
    depth_target: rg.RenderGraphTextureHandle,
    resources: *const Resources,
    scene: *const RenderScene2,
    camera: SceneCamera,
    render_graph: *rg.RenderGraph,
) !void {
    const material_info_buffer = try render_graph.importBuffer(resources.material_buffer.?);

    var render_pass = try rg.RenderPass.init(temp_allocator, "Scene Draw Pass");
    try render_pass.addColorAttachment(.{
        .texture = color_target,
        .clear = .{ .float_32 = .{ 0.0, 0.25, 0.25, 1.0 } },
        .store = true,
    });
    render_pass.addDepthAttachment(.{
        .texture = depth_target,
        .clear = 1.0,
        .store = true,
    });

    const build_data = try temp_allocator.create(DrawLegacy.Data);
    build_data.* = .{
        .camera = camera,

        .opaque_draw_pipeline = self.opaque_draw_pipeline,
        .material_info_buffer = material_info_buffer,

        .resources = resources,
        .scene = scene,
    };
    render_pass.addBuildFn(DrawLegacy.buildCommandBuffer, build_data);

    try render_graph.render_passes.append(render_graph.allocator, render_pass);
}

pub const DrawLegacy = struct {
    pub const Data = struct {
        camera: SceneCamera,
        opaque_draw_pipeline: vk.Pipeline,
        material_info_buffer: rg.RenderGraphBufferHandle,
        resources: *const Resources,
        scene: *const RenderScene2,
    };

    const PushConstants = extern struct {
        view_projection_matrix: zm.Mat,
        model_matrix: zm.Mat,
        material_info_binding: u32,
        material_index: u32,
    };

    fn buildCommandBuffer(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
        const data: *Data = @ptrCast(@alignCast(build_data.?));

        const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
        const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
        const aspect_ratio: f32 = width_float / height_float;
        const view_matrix = data.camera.transform.getViewMatrix();
        var projection_matrix = data.camera.settings.getProjectionMatrix(aspect_ratio);
        projection_matrix[1][1] *= -1.0;
        const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

        const material_info_buffer = resources.buffers[data.material_info_buffer.index];

        command_buffer.bindPipeline(.graphics, data.opaque_draw_pipeline);

        const vertex_buffer = device.buffers.get(data.resources.meshes2.vertex_buffer.buffer).?.handle;
        const index_buffer = device.buffers.get(data.resources.meshes2.index_buffer.buffer).?.handle;

        const base_vertex_offset: u64 = 0;
        command_buffer.bindVertexBuffers(0, 1, @ptrCast(&vertex_buffer), @ptrCast(&base_vertex_offset));
        command_buffer.bindIndexBuffer(index_buffer, 0, .uint32);

        var instance_iter = data.scene.instances.iterator();
        while (instance_iter.next_value()) |instance| {
            if (!instance.visable) {
                continue;
            }

            const model_matrix = instance.transform.getModelMatrix();

            const mesh_asset = data.resources.meshes2.map.get(instance.mesh) orelse continue;
            const vertex_offset: u32 = @intCast(mesh_asset.vertices.offset);
            const index_offset: u32 = @intCast(mesh_asset.indices.offset);

            for (mesh_asset.cpu_primitives, instance.materials.slice()) |primitive, material| {
                const material_entry = data.resources.material_map.get(material) orelse continue;
                if (material_entry.material.alpha_mode != .alpha_opaque) continue;

                const push_data: PushConstants = .{
                    .view_projection_matrix = view_projection_matrix,
                    .model_matrix = model_matrix,
                    .material_info_binding = material_info_buffer.storage_binding.?,
                    .material_index = material_entry.buffer_index.?,
                };
                command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(PushConstants), &push_data);
                command_buffer.drawIndexed(
                    primitive.index_count,
                    1,
                    index_offset + primitive.index_offset,
                    @intCast(vertex_offset + primitive.vertex_offset),
                    0,
                );
            }
        }
    }
};
