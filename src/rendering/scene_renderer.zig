const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;
const culling = @import("culling.zig");
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

opaque_direct_mesh_pipeline: vk.Pipeline,
opaque_direct_mesh_pipeline_load: vk.Pipeline,
opaque_mesh_shader_pipeline: vk.Pipeline,

build_indirect_comp_pipeline: vk.Pipeline,
opaque_draw_indirect_comp_pipeline: vk.Pipeline,

//Debug Values
indirect_draw: bool = true,
vertex_storage_load: bool = false,
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

    const direct_vertex_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/mesh.vert.asset"));
    defer device.device.proxy.destroyShaderModule(direct_vertex_shader, null);

    const direct_load_vertex_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/mesh_vert_load.vert.asset"));
    defer device.device.proxy.destroyShaderModule(direct_load_vertex_shader, null);

    const opaque_fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/opaque.frag.asset"));
    defer device.device.proxy.destroyShaderModule(opaque_fragment_shader, null);

    const pipeline_config: Pipeline.PipelineConfig = .{
        .color_format = color_format,
        .depth_format = depth_format,
        .cull_mode = .{ .back_bit = true },
    };

    const opaque_direct_mesh_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        pipeline_config,
        .{
            .attributes = &attributes,
            .bindings = &bindings,
        },
        direct_vertex_shader,
        opaque_fragment_shader,
    );

    const opaque_direct_mesh_pipeline_load = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        pipeline_config,
        .{},
        direct_load_vertex_shader,
        opaque_fragment_shader,
    );

    const mesh_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/mesh.mesh.asset"));
    defer device.device.proxy.destroyShaderModule(mesh_shader, null);

    const opaque_mesh_shader_pipeline = try Pipeline.createMeshShaderPipeline(
        device.device.proxy,
        pipeline_layout,
        pipeline_config,
        null,
        mesh_shader,
        opaque_fragment_shader,
    );

    const build_indirect_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/build_indirect.comp.asset"));
    defer device.device.proxy.destroyShaderModule(build_indirect_shader, null);
    const build_indirect_comp_pipeline = try Pipeline.createComputePipeline(device.device.proxy, pipeline_layout, build_indirect_shader);

    const draw_indirect_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/draw_indirect.vert.asset"));
    defer device.device.proxy.destroyShaderModule(draw_indirect_shader, null);
    const opaque_draw_indirect_comp_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        pipeline_config,
        .{},
        draw_indirect_shader,
        opaque_fragment_shader,
    );

    return .{
        .allocator = allocator,
        .device = device,
        .opaque_direct_mesh_pipeline = opaque_direct_mesh_pipeline,
        .opaque_direct_mesh_pipeline_load = opaque_direct_mesh_pipeline_load,
        .opaque_mesh_shader_pipeline = opaque_mesh_shader_pipeline,
        .build_indirect_comp_pipeline = build_indirect_comp_pipeline,
        .opaque_draw_indirect_comp_pipeline = opaque_draw_indirect_comp_pipeline,
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.opaque_direct_mesh_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.opaque_direct_mesh_pipeline_load, null);
    self.device.device.proxy.destroyPipeline(self.opaque_mesh_shader_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.build_indirect_comp_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.opaque_draw_indirect_comp_pipeline, null);
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

    if (self.indirect_draw) {
        const max_draw_count = scene.getIndirectDrawCount();
        const indrect_command_buffer = try render_graph.createTransientBuffer(.{ .size = max_draw_count * @sizeOf(vk.DrawIndirectCommand), .usage = .{ .storage_buffer_bit = true, .indirect_buffer_bit = true } });
        const indirect_info_buffer = try render_graph.createTransientBuffer(.{ .size = max_draw_count * @sizeOf(BuildIndirect.DrawInfo), .usage = .{ .storage_buffer_bit = true } });

        {
            var render_pass = try rg.RenderPass.init(temp_allocator, "Indirect Build Pass");

            const build_data = try temp_allocator.create(BuildIndirect.Data);
            build_data.* = .{
                .instance_count = @intCast(scene.instances.items.len),
                .pipeline = self.build_indirect_comp_pipeline,
                .scene_instance_buffer = scene_instance_buffer,
                .mesh_info_buffer = mesh_info_buffer,
                .indrect_command_buffer = indrect_command_buffer,
                .indirect_info_buffer = indirect_info_buffer,
            };
            render_pass.addBuildFn(BuildIndirect.buildCommandBuffer, build_data);

            try render_graph.render_passes.append(render_graph.allocator, render_pass);
        }

        {
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
                .camera_transform = camera_transform,

                .max_draw_count = @intCast(max_draw_count),
                .opaque_draw_pipeline = self.opaque_draw_indirect_comp_pipeline,
                .mesh_info_buffer = mesh_info_buffer,
                .material_info_buffer = material_info_buffer,
                .indrect_command_buffer = indrect_command_buffer,
                .indirect_info_buffer = indirect_info_buffer,
            };
            render_pass.addBuildFn(DrawIndirect.buildCommandBuffer, build_data);

            try render_graph.render_passes.append(render_graph.allocator, render_pass);
        }
    } else {
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

            .mesh_info_buffer = resources.meshes.mesh_info_buffer,
            .material_buffer = resources.material_buffer.?,

            .camera = camera,
            .camera_transform = camera_transform,
            .scene = scene,
        };
        render_pass.addBuildFn(buildCommandBufferDirect, scene_build_data);

        try render_graph.render_passes.append(render_graph.allocator, render_pass);
    }
}

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
        indrect_command_buffer: rg.RenderGraphBufferHandle,
        indirect_info_buffer: rg.RenderGraphBufferHandle,
    };

    const PushConstants = extern struct {
        scene_instance_binding: u32,
        mesh_info_binding: u32,

        indrect_command_binding: u32,
        indirect_info_binding: u32,
    };

    fn buildCommandBuffer(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
        _ = raster_pass_extent; // autofix

        const data: *Data = @ptrCast(@alignCast(build_data.?));

        const scene_instance_buffer = resources.buffers[data.scene_instance_buffer.index];
        const mesh_info_buffer = resources.buffers[data.mesh_info_buffer.index];
        const indrect_command_buffer = resources.buffers[data.indrect_command_buffer.index];
        const indirect_info_buffer = resources.buffers[data.indirect_info_buffer.index];

        command_buffer.bindPipeline(.compute, data.pipeline);

        const push_data: PushConstants = .{
            .scene_instance_binding = scene_instance_buffer.storage_binding.?,
            .mesh_info_binding = mesh_info_buffer.storage_binding.?,
            .indrect_command_binding = indrect_command_buffer.storage_binding.?,
            .indirect_info_binding = indirect_info_buffer.storage_binding.?,
        };
        command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(PushConstants), &push_data);

        command_buffer.dispatch(data.instance_count, 1, 1);
    }
};

pub const DrawIndirect = struct {
    pub const Data = struct {
        camera: Camera,
        camera_transform: Transform,

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
        indirect_info_binding: u32,
    };

    fn buildCommandBuffer(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
        const data: *Data = @ptrCast(@alignCast(build_data.?));

        const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
        const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
        const aspect_ratio: f32 = width_float / height_float;
        const view_matrix = data.camera_transform.getViewMatrix();
        var projection_matrix = data.camera.getProjectionMatrix(aspect_ratio);
        projection_matrix[1][1] *= -1.0;
        const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

        const mesh_info_buffer = resources.buffers[data.mesh_info_buffer.index];
        const material_info_buffer = resources.buffers[data.material_info_buffer.index];
        const indrect_command_buffer = resources.buffers[data.indrect_command_buffer.index];
        const indirect_info_buffer = resources.buffers[data.indirect_info_buffer.index];

        if (data.opaque_draw_pipeline == .null_handle) {
            return;
        }

        command_buffer.bindPipeline(.graphics, data.opaque_draw_pipeline);

        const push_data: PushConstants = .{
            .view_projection_matrix = view_projection_matrix,
            .mesh_info_binding = mesh_info_buffer.storage_binding.?,
            .material_info_binding = material_info_buffer.storage_binding.?,
            .indirect_info_binding = indirect_info_buffer.storage_binding.?,
        };
        command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(PushConstants), &push_data);
        command_buffer.drawIndirect(indrect_command_buffer.handle, 0, data.max_draw_count, @sizeOf(vk.DrawIndirectCommand));
    }
};

pub const BuildCommandBufferData = struct {
    self: *Self,
    resources: *const Resources,

    mesh_info_buffer: Backend.BufferHandle,
    material_buffer: Backend.BufferHandle,

    camera: Camera,
    camera_transform: Transform,
    scene: *const RenderScene,
};

const PushData2 = extern struct {
    view_projection_matrix: zm.Mat,
    mesh_info_binding: u32,
    material_binding: u32,

    model_matrix: zm.Mat,
    mesh_index: u32,
    primitive_index: u32,
    material_index: u32,
};

fn buildCommandBufferDirect(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = resources; // autofix
    const data: *BuildCommandBufferData = @ptrCast(@alignCast(build_data.?));
    const self = data.self;

    const scene_geometry_buffer = device.buffers.get(data.resources.meshes.geometry_buffer).?;
    const mesh_info_buffer = device.buffers.get(data.mesh_info_buffer).?;
    const material_buffer = device.buffers.get(data.material_buffer).?;

    const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
    const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
    const aspect_ratio: f32 = width_float / height_float;
    const view_matrix = data.camera_transform.getViewMatrix();
    var projection_matrix = data.camera.getProjectionMatrix(aspect_ratio);
    projection_matrix[1][1] *= -1.0;
    const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

    for (data.scene.instances.items) |static_mesh| {
        if (static_mesh.component.visable == false) {
            continue;
        }

        if (data.resources.meshes.map.get(static_mesh.component.mesh)) |mesh| {
            if (self.mesh_shading) {
                command_buffer.bindPipeline(.graphics, self.opaque_mesh_shader_pipeline);
            } else if (!self.vertex_storage_load) {
                command_buffer.bindPipeline(.graphics, self.opaque_direct_mesh_pipeline);
                const scene_geometry_handle = scene_geometry_buffer.handle;
                command_buffer.bindIndexBuffer(scene_geometry_handle, mesh.indices.offset, .uint32);
                command_buffer.bindVertexBuffers(0, 1, &.{scene_geometry_handle}, &.{mesh.vertices.offset});
            } else {
                command_buffer.bindPipeline(.graphics, self.opaque_direct_mesh_pipeline_load);
            }

            const model_matrix = static_mesh.transform.getModelMatrix();
            const materials = static_mesh.component.materials.constSlice();
            for (mesh.cpu_primitives, materials, 0..) |primitive, material, primitive_index| {
                if (data.resources.material_map.get(material)) |mat_entry| {
                    if (mat_entry.material.alpha_mode != .alpha_opaque) {
                        continue;
                    }

                    const push_data = PushData2{
                        .view_projection_matrix = view_projection_matrix,
                        .mesh_info_binding = mesh_info_buffer.storage_binding.?.index,
                        .material_binding = material_buffer.storage_binding.?.index,

                        .model_matrix = model_matrix,
                        .mesh_index = mesh.index,
                        .primitive_index = @intCast(primitive_index),
                        .material_index = mat_entry.buffer_index.?,
                    };
                    command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(PushData2), &push_data);

                    if (self.mesh_shading) {
                        command_buffer.drawMeshTasksEXT(primitive.meshlet_count, 1, 1);
                    } else if (self.vertex_storage_load) {
                        command_buffer.draw(primitive.index_count, 1, 0, 0);
                    } else {
                        command_buffer.drawIndexed(primitive.index_count, 1, primitive.index_offset, @intCast(primitive.vertex_offset), 0);
                    }
                }
            }
        }
    }
}
