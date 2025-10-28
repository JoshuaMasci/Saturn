const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");
const SceneCamera = @import("camera.zig").SceneCamera;
const CullData = @import("culling.zig").CullData;
const RenderScene = @import("scene.zig");
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

build_indirect_comp_pipeline: vk.Pipeline,
opaque_draw_indirect_pipeline: vk.Pipeline,
opaque_draw_task_mesh_pipeline: ?vk.Pipeline,

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
    const opaque_fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/opaque.frag.asset"));
    defer device.device.proxy.destroyShaderModule(opaque_fragment_shader, null);

    const pipeline_config: Pipeline.PipelineConfig = .{
        .color_format = color_format,
        .depth_format = depth_format,
        .cull_mode = .{ .back_bit = true },
    };

    const build_indirect_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/build_indirect.comp.asset"));
    defer device.device.proxy.destroyShaderModule(build_indirect_shader, null);
    const build_indirect_comp_pipeline = try Pipeline.createComputePipeline(device.device.proxy, pipeline_layout, build_indirect_shader);

    const draw_indirect_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/draw_indirect.vert.asset"));
    defer device.device.proxy.destroyShaderModule(draw_indirect_shader, null);
    const opaque_draw_indirect_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        pipeline_config,
        .{},
        draw_indirect_shader,
        opaque_fragment_shader,
    );

    var opaque_draw_task_mesh_pipeline: ?vk.Pipeline = null;
    if (device.device.extensions.mesh_shading) {
        const draw_indirect_task_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/draw_indirect.task.asset"));
        defer device.device.proxy.destroyShaderModule(draw_indirect_task_shader, null);

        const draw_indirect_mesh_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/draw_indirect.mesh.asset"));
        defer device.device.proxy.destroyShaderModule(draw_indirect_mesh_shader, null);

        opaque_draw_task_mesh_pipeline = try Pipeline.createMeshShaderPipeline(
            device.device.proxy,
            pipeline_layout,
            pipeline_config,
            draw_indirect_task_shader,
            draw_indirect_mesh_shader,
            opaque_fragment_shader,
        );
    }

    return .{
        .allocator = allocator,
        .device = device,
        .build_indirect_comp_pipeline = build_indirect_comp_pipeline,
        .opaque_draw_indirect_pipeline = opaque_draw_indirect_pipeline,
        .opaque_draw_task_mesh_pipeline = opaque_draw_task_mesh_pipeline,
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.build_indirect_comp_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.opaque_draw_indirect_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.opaque_draw_task_mesh_pipeline orelse .null_handle, null);
}

pub fn createRenderPass(
    self: *Self,
    temp_allocator: std.mem.Allocator,
    color_target: rg.RenderGraphTextureHandle,
    depth_target: rg.RenderGraphTextureHandle,
    resources: *const Resources,
    scene: *const RenderScene,
    camera: SceneCamera,
    render_graph: *rg.RenderGraph,
) !void {
    if (scene.instances.items.len == 0) {
        var render_pass = try rg.RenderPass.init(temp_allocator, "Empty Scene Pass");
        try render_pass.addColorAttachment(.{
            .texture = color_target,
            .clear = .{ .float_32 = @splat(0.0) },
            .store = true,
        });
        try render_graph.render_passes.append(render_graph.allocator, render_pass);
        return;
    }

    const scene_instance_buffer = try render_graph.importBuffer(scene.instance_buffer.?);
    const mesh_info_buffer = try render_graph.importBuffer(resources.meshes.mesh_info_buffer);
    const material_info_buffer = try render_graph.importBuffer(resources.material_buffer.?);

    {
        const max_draw_count = scene.getIndirectDrawCount();
        const indirect_draw_count_buffer = try render_graph.createTransientBuffer(.{ .size = 16, .usage = .{ .storage_buffer_bit = true, .indirect_buffer_bit = true } });
        const indirect_command_buffer = try render_graph.createTransientBuffer(.{ .size = max_draw_count * @sizeOf(vk.DrawIndirectCommand), .usage = .{ .storage_buffer_bit = true, .indirect_buffer_bit = true } });
        const indirect_info_buffer = try render_graph.createTransientBuffer(.{ .size = max_draw_count * @sizeOf(BuildIndirect.DrawInfo), .usage = .{ .storage_buffer_bit = true } });

        {
            var render_pass = try rg.RenderPass.init(temp_allocator, "Indirect Build Pass");

            const build_data = try temp_allocator.create(BuildIndirect.Data);
            build_data.* = .{
                .instance_count = @intCast(scene.instances.items.len),
                .pipeline = self.build_indirect_comp_pipeline,
                .scene_instance_buffer = scene_instance_buffer,
                .mesh_info_buffer = mesh_info_buffer,
                .indirect_draw_count_buffer = indirect_draw_count_buffer,
                .indirect_command_buffer = indirect_command_buffer,
                .indirect_info_buffer = indirect_info_buffer,

                .culling_enabled = self.gpu_culling,
                .camera = self.locked_culling_info orelse camera,
                .target_texture = color_target,
            };
            render_pass.addBuildFn(BuildIndirect.buildCommandBuffer, build_data);

            try render_graph.render_passes.append(render_graph.allocator, render_pass);
        }

        if (self.mesh_shading and self.opaque_draw_task_mesh_pipeline != null) {
            var render_pass = try rg.RenderPass.init(temp_allocator, "Mesh Shading Draw Pass");
            try render_pass.addColorAttachment(.{
                .texture = color_target,
                .clear = .{ .float_32 = .{ 0.25, 0.0, 0.25, 1.0 } },
                .store = true,
            });
            render_pass.addDepthAttachment(.{
                .texture = depth_target,
                .clear = 1.0,
                .store = true,
            });

            const build_data = try temp_allocator.create(DrawMeshTask.Data);
            build_data.* = .{
                .camera = camera,

                .max_draw_count = @intCast(max_draw_count),
                .opaque_draw_pipeline = self.opaque_draw_task_mesh_pipeline.?,
                .mesh_info_buffer = mesh_info_buffer,
                .material_info_buffer = material_info_buffer,
                .indrect_command_buffer = indirect_command_buffer,
                .indirect_info_buffer = indirect_info_buffer,
            };
            render_pass.addBuildFn(DrawMeshTask.buildCommandBuffer, build_data);

            try render_graph.render_passes.append(render_graph.allocator, render_pass);
        } else {
            var render_pass = try rg.RenderPass.init(temp_allocator, "Indirect Draw Pass");
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

            const build_data = try temp_allocator.create(DrawIndirect.Data);
            build_data.* = .{
                .camera = camera,

                .max_draw_count = @intCast(max_draw_count),
                .opaque_draw_pipeline = self.opaque_draw_indirect_pipeline,
                .mesh_info_buffer = mesh_info_buffer,
                .material_info_buffer = material_info_buffer,
                .indirect_draw_count_buffer = indirect_draw_count_buffer,
                .indirect_command_buffer = indirect_command_buffer,
                .indirect_info_buffer = indirect_info_buffer,
            };
            render_pass.addBuildFn(DrawIndirect.buildCommandBuffer, build_data);

            try render_graph.render_passes.append(render_graph.allocator, render_pass);
        }
    }
}

/// Build the required buffers for indirect dispatches
pub const BuildIndirect = struct {
    //CPU version of IndirectDrawInfo, only used for size calculations
    pub const DrawInfo = extern struct {
        model_matrix: zm.Mat,
        mesh_index: u32,
        primitive_index: u32,
        material_index: u32,
        pad: u32,
    };

    pub const Data = struct {
        instance_count: u32,
        pipeline: vk.Pipeline,
        scene_instance_buffer: rg.RenderGraphBufferHandle,
        mesh_info_buffer: rg.RenderGraphBufferHandle,
        indirect_draw_count_buffer: rg.RenderGraphBufferHandle,
        indirect_command_buffer: rg.RenderGraphBufferHandle,
        indirect_info_buffer: rg.RenderGraphBufferHandle,

        culling_enabled: bool,
        camera: SceneCamera,
        target_texture: rg.RenderGraphTextureHandle,
    };

    const PushConstants = extern struct {
        scene_instance_binding: u32,
        mesh_info_binding: u32,
        indirect_draw_count_binding: u32,
        indrect_command_binding: u32,
        indirect_info_binding: u32,
        pad0: u32 = 0,
        pad1: u32 = 0,
        culling: u32,
        cull_data: CullData,
    };

    fn buildCommandBuffer(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
        _ = raster_pass_extent; // autofix

        const data: *Data = @ptrCast(@alignCast(build_data.?));

        const scene_instance_buffer = resources.buffers[data.scene_instance_buffer.index];
        const mesh_info_buffer = resources.buffers[data.mesh_info_buffer.index];
        const indirect_draw_count_buffer = resources.buffers[data.indirect_draw_count_buffer.index];
        const indrect_command_buffer = resources.buffers[data.indirect_command_buffer.index];
        const indirect_info_buffer = resources.buffers[data.indirect_info_buffer.index];

        const target_texture = resources.textures[data.target_texture.index];
        const target_width: f32 = @floatFromInt(target_texture.extent.width);
        const target_height: f32 = @floatFromInt(target_texture.extent.height);
        const aspect_ratio: f32 = target_width / target_height;

        command_buffer.bindPipeline(.compute, data.pipeline);

        const push_data: PushConstants = .{
            .scene_instance_binding = scene_instance_buffer.storage_binding.?,
            .mesh_info_binding = mesh_info_buffer.storage_binding.?,
            .indirect_draw_count_binding = indirect_draw_count_buffer.storage_binding.?,
            .indrect_command_binding = indrect_command_buffer.storage_binding.?,
            .indirect_info_binding = indirect_info_buffer.storage_binding.?,
            .culling = @intFromBool(data.culling_enabled),
            .cull_data = .init(data.camera, aspect_ratio),
        };
        command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(PushConstants), &push_data);

        command_buffer.dispatch(data.instance_count, 1, 1);
    }
};

/// Draws opaque geometry using vkCmdDrawIndirect
pub const DrawIndirect = struct {
    pub const Data = struct {
        camera: SceneCamera,

        max_draw_count: u32,
        opaque_draw_pipeline: vk.Pipeline,
        mesh_info_buffer: rg.RenderGraphBufferHandle,
        material_info_buffer: rg.RenderGraphBufferHandle,
        indirect_draw_count_buffer: rg.RenderGraphBufferHandle,
        indirect_command_buffer: rg.RenderGraphBufferHandle,
        indirect_info_buffer: rg.RenderGraphBufferHandle,
    };

    const PushConstants = extern struct {
        view_projection_matrix: zm.Mat,
        mesh_info_binding: u32,
        material_info_binding: u32,
        indirect_info_binding: u32,
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

        const mesh_info_buffer = resources.buffers[data.mesh_info_buffer.index];
        const material_info_buffer = resources.buffers[data.material_info_buffer.index];
        const indirect_draw_count_buffer = resources.buffers[data.indirect_draw_count_buffer.index];
        const indirect_command_buffer = resources.buffers[data.indirect_command_buffer.index];
        const indirect_info_buffer = resources.buffers[data.indirect_info_buffer.index];

        command_buffer.bindPipeline(.graphics, data.opaque_draw_pipeline);

        const push_data: PushConstants = .{
            .view_projection_matrix = view_projection_matrix,
            .mesh_info_binding = mesh_info_buffer.storage_binding.?,
            .material_info_binding = material_info_buffer.storage_binding.?,
            .indirect_info_binding = indirect_info_buffer.storage_binding.?,
        };
        command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(PushConstants), &push_data);
        //command_buffer.drawIndirect(indirect_command_buffer.handle, 0, data.max_draw_count, @sizeOf(vk.DrawIndirectCommand));
        command_buffer.drawIndirectCount(indirect_command_buffer.handle, 0, indirect_draw_count_buffer.handle, 0, data.max_draw_count, @sizeOf(vk.DrawIndirectCommand));
    }
};

/// Draws opaque geometry using drawMeshTasksEXT
pub const DrawMeshTask = struct {
    pub const Data = struct {
        camera: SceneCamera,

        max_draw_count: u32,
        opaque_draw_pipeline: vk.Pipeline,
        mesh_info_buffer: rg.RenderGraphBufferHandle,
        material_info_buffer: rg.RenderGraphBufferHandle,
        indrect_command_buffer: rg.RenderGraphBufferHandle,
        indirect_info_buffer: rg.RenderGraphBufferHandle,
    };

    const PushConstants = extern struct {
        view_projection_matrix: zm.Mat,
        mesh_info_binding: u32,
        material_info_binding: u32,
        indirect_command_binding: u32,
        indirect_info_binding: u32,
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

        const mesh_info_buffer = resources.buffers[data.mesh_info_buffer.index];
        const material_info_buffer = resources.buffers[data.material_info_buffer.index];
        const indrect_command_buffer = resources.buffers[data.indrect_command_buffer.index];
        const indirect_info_buffer = resources.buffers[data.indirect_info_buffer.index];

        command_buffer.bindPipeline(.graphics, data.opaque_draw_pipeline);

        const push_data: PushConstants = .{
            .view_projection_matrix = view_projection_matrix,
            .mesh_info_binding = mesh_info_buffer.storage_binding.?,
            .material_info_binding = material_info_buffer.storage_binding.?,
            .indirect_command_binding = indrect_command_buffer.storage_binding.?,
            .indirect_info_binding = indirect_info_buffer.storage_binding.?,
        };
        command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(PushConstants), &push_data);
        command_buffer.drawMeshTasksEXT(data.max_draw_count, 1, 1);
    }
};
