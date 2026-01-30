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

const Self = @This();

allocator: std.mem.Allocator,
device: *Backend,

opaque_draw_legacy_pipeline: vk.Pipeline,

build_indirect_pipeline: vk.Pipeline,
draw_opaque_indirect_pipeline: vk.Pipeline,

//Debug Values
indirect: bool = true,
culling: bool = true,
locked_culling_info: ?SceneCamera = null,

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

    const pipeline_config: Pipeline.PipelineConfig = .{
        .color_format = color_format,
        .depth_format = depth_format,
        .cull_mode = .{ .back_bit = true },
    };

    const draw_legacy_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/glsl/draw_legacy.vert.asset"));
    defer device.device.proxy.destroyShaderModule(draw_legacy_shader, null);

    const opaque_legacy_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/glsl/opaque_legacy.frag.asset"));
    defer device.device.proxy.destroyShaderModule(opaque_legacy_shader, null);

    const opaque_draw_legacy_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        pipeline_config,
        .{
            .bindings = &bindings,
            .attributes = &attributes,
        },
        draw_legacy_shader,
        opaque_legacy_shader,
    );
    errdefer device.device.proxy.destroyPipeline(opaque_draw_legacy_pipeline, null);

    const build_indirect_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/glsl/build_indirect.comp.asset"));
    defer device.device.proxy.destroyShaderModule(build_indirect_shader, null);
    const build_indirect_pipeline = try Pipeline.createComputePipeline(device.device.proxy, pipeline_layout, build_indirect_shader);

    const draw_indirect_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/glsl/draw_indirect.vert.asset"));
    defer device.device.proxy.destroyShaderModule(draw_indirect_shader, null);

    const opaque_indirect_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/glsl/opaque_indirect.frag.asset"));
    defer device.device.proxy.destroyShaderModule(opaque_indirect_shader, null);

    const draw_opaque_indirect_pipeline = try Pipeline.createGraphicsPipeline(
        device.device.proxy,
        pipeline_layout,
        pipeline_config,
        .{
            .bindings = &bindings,
            .attributes = &attributes,
        },
        draw_indirect_shader,
        opaque_indirect_shader,
    );
    errdefer device.device.proxy.destroyPipeline(draw_opaque_indirect_pipeline, null);

    return .{
        .allocator = allocator,
        .device = device,

        .opaque_draw_legacy_pipeline = opaque_draw_legacy_pipeline,

        .build_indirect_pipeline = build_indirect_pipeline,
        .draw_opaque_indirect_pipeline = draw_opaque_indirect_pipeline,
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.opaque_draw_legacy_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.build_indirect_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.draw_opaque_indirect_pipeline, null);
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
    const material_info_buffer = try render_graph.importBuffer(resources.material_buffer.?);
    const mesh_info_buffer = try render_graph.importBuffer(resources.meshes.mesh_info_buffer);

    if (self.indirect) {
        const scene_buffers = try SceneBuffers.init(scene, temp_allocator, resources, render_graph);

        const build_data = try temp_allocator.create(DrawIndirect.Data);
        build_data.* = .{
            .camera = camera,
            .culling = null,
            .build_pipeline = self.build_indirect_pipeline,

            .material_info_buffer = material_info_buffer,
            .mesh_info_buffer = mesh_info_buffer,

            .opaque_draw_pipeline = self.draw_opaque_indirect_pipeline,
            .vertex_buffer = try render_graph.importBuffer(resources.meshes.vertex_buffer.buffer),
            .index_buffer = try render_graph.importBuffer(resources.meshes.index_buffer.buffer),

            .scene_buffers = scene_buffers,
        };

        if (self.culling) {
            build_data.*.culling = .{
                .camera = self.locked_culling_info orelse camera,
                .target_texture = color_target,
            };
        }

        {
            var render_pass = try rg.RenderPass.init(temp_allocator, "Indirect Build Pass");
            render_pass.addBuildFn(DrawIndirect.buildPass, build_data);
            try render_graph.render_passes.append(render_graph.allocator, render_pass);
        }

        {
            var render_pass = try rg.RenderPass.init(temp_allocator, "Indirect Draw Pass");
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

            render_pass.addBuildFn(DrawIndirect.drawPass, build_data);
            try render_graph.render_passes.append(render_graph.allocator, render_pass);
        }
    } else {
        var render_pass = try rg.RenderPass.init(temp_allocator, "Legacy Draw Pass");
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

            .opaque_draw_pipeline = self.opaque_draw_legacy_pipeline,
            .material_info_buffer = material_info_buffer,

            .resources = resources,
            .scene = scene,
        };
        render_pass.addBuildFn(DrawLegacy.buildCommandBuffer, build_data);

        try render_graph.render_passes.append(render_graph.allocator, render_pass);
    }
}

pub const DrawLegacy = struct {
    pub const Data = struct {
        camera: SceneCamera,
        opaque_draw_pipeline: vk.Pipeline,
        material_info_buffer: rg.RenderGraphBufferHandle,
        resources: *const Resources,
        scene: *const RenderScene,
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

        const material_info_buffer = resources.getBuffer(data.material_info_buffer).?;

        command_buffer.bindPipeline(.graphics, data.opaque_draw_pipeline);

        const vertex_buffer = device.buffers.get(data.resources.meshes.vertex_buffer.buffer).?.handle;
        const index_buffer = device.buffers.get(data.resources.meshes.index_buffer.buffer).?.handle;

        const base_vertex_offset: u64 = 0;
        command_buffer.bindVertexBuffers(0, 1, @ptrCast(&vertex_buffer), @ptrCast(&base_vertex_offset));
        command_buffer.bindIndexBuffer(index_buffer, 0, .uint32);

        var instance_iter = data.scene.instances.iterator();
        while (instance_iter.next_value()) |instance| {
            if (!instance.visable) {
                continue;
            }

            const model_matrix = instance.transform.getModelMatrix();

            const mesh_asset = data.resources.meshes.map.get(instance.mesh) orelse continue;
            const vertex_offset: u32 = @intCast(mesh_asset.vertices.offset);
            const index_offset: u32 = @intCast(mesh_asset.indices.offset);

            for (mesh_asset.cpu_primitives, instance.primitives.slice()) |primitive, primtive| {
                const material_entry = data.resources.material_map.get(primtive.material_handle) orelse continue;
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

//TODO: cache and update rather than rebuild every frame
pub const SceneBuffers = struct {
    pub const GpuInstance = extern struct {
        model_matrix: zm.Mat,
        normal_matrix: zm.Mat,
        mesh_index: u32,
        visable: u32,
        pad0: u32 = 0,
        pad1: u32 = 0,
    };
    pub const GpuPrimitiveInstance = extern struct {
        instance_index: u32,
        primitive_index: u32,
        material_instance_index: u32,
        pad0: u32 = 0,
    };

    pub const DrawIndexedIndirectCommandInfo = extern struct {
        indexCount: u32,
        instanceCount: u32,
        firstIndex: u32,
        vertexOffset: i32,
        firstInstance: u32,
        instance_index: u32,
        material_index: u32,
    };

    instance_buffer: rg.RenderGraphBufferHandle,
    indirect_draw_counts_buffer: rg.RenderGraphBufferHandle,

    opaque_primitves_count: u32,
    opaque_primitves_buffer: rg.RenderGraphBufferHandle,
    opaque_indirect_cmd_info: rg.RenderGraphBufferHandle,

    pub fn init(
        scene: *const RenderScene,
        temp_allocator: std.mem.Allocator,
        resources: *const Resources,
        render_graph: *rg.RenderGraph,
    ) !@This() {
        _ = temp_allocator; // autofix
        _ = resources; // autofix
        const opaque_primitive_count = scene.opaque_primitives_buffer.count();

        return .{
            .instance_buffer = try render_graph.importBuffer(scene.scene_instance_buffer.gpu),
            .indirect_draw_counts_buffer = try render_graph.createTransientBuffer(.{
                .size = @sizeOf(u32) * 16,
                .usage = .{ .indirect_buffer_bit = true, .shader_device_address_bit = true },
            }),
            .opaque_primitves_count = @intCast(opaque_primitive_count),
            .opaque_primitves_buffer = try render_graph.importBuffer(scene.opaque_primitives_buffer.gpu),
            .opaque_indirect_cmd_info = try render_graph.createTransientBuffer(.{
                .size = @sizeOf(DrawIndexedIndirectCommandInfo) * opaque_primitive_count,
                .usage = .{ .indirect_buffer_bit = true, .shader_device_address_bit = true },
            }),
        };
    }
};

pub const DrawIndirect = struct {
    pub const Data = struct {
        camera: SceneCamera,
        culling: ?struct {
            camera: SceneCamera,
            target_texture: rg.RenderGraphTextureHandle, //Needed to calc aspect ratio
        },
        build_pipeline: vk.Pipeline,
        mesh_info_buffer: rg.RenderGraphBufferHandle,
        material_info_buffer: rg.RenderGraphBufferHandle,

        opaque_draw_pipeline: vk.Pipeline,
        vertex_buffer: rg.RenderGraphBufferHandle,
        index_buffer: rg.RenderGraphBufferHandle,

        scene_buffers: SceneBuffers,
    };

    pub const BuildPushData = extern struct {
        indirect_draw_count_index: u32,
        indirect_draw_counts_ptr: vk.DeviceAddress,

        mesh_infos_ptr: vk.DeviceAddress,
        scene_instances_ptr: vk.DeviceAddress,
        scene_primitives_ptr: vk.DeviceAddress,

        indirect_command_infos_ptr: vk.DeviceAddress,

        culling: u32,
        cull_data: CullData,
    };

    fn buildPass(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
        _ = raster_pass_extent; // autofix
        const data: *Data = @ptrCast(@alignCast(build_data.?));

        var cull_data: ?CullData = null;
        if (data.culling) |culling| {
            const target_texture = resources.textures[culling.target_texture.index];
            const target_width: f32 = @floatFromInt(target_texture.extent.width);
            const target_height: f32 = @floatFromInt(target_texture.extent.height);
            const aspect_ratio: f32 = target_width / target_height;
            cull_data = .init(culling.camera, aspect_ratio);
        }

        const mesh_info_buffer = resources.getBuffer(data.mesh_info_buffer).?;
        const instance_buffer = resources.getBuffer(data.scene_buffers.instance_buffer).?;
        const indirect_draw_counts_buffer = resources.getBuffer(data.scene_buffers.indirect_draw_counts_buffer).?;

        command_buffer.bindPipeline(.compute, data.build_pipeline);

        const opaque_primitves_buffer = resources.getBuffer(data.scene_buffers.opaque_primitves_buffer).?;
        const opaque_indirect_cmd_info = resources.getBuffer(data.scene_buffers.opaque_indirect_cmd_info).?;

        const push_data: BuildPushData = .{
            .indirect_draw_count_index = 0,
            .indirect_draw_counts_ptr = indirect_draw_counts_buffer.device_address.?,

            .mesh_infos_ptr = mesh_info_buffer.device_address.?,
            .scene_instances_ptr = instance_buffer.device_address.?,
            .scene_primitives_ptr = opaque_primitves_buffer.device_address.?,

            .indirect_command_infos_ptr = opaque_indirect_cmd_info.device_address.?,

            .culling = if (data.culling != null) 1 else 0,
            .cull_data = cull_data orelse undefined,
        };
        command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(BuildPushData), &push_data);

        command_buffer.dispatch(data.scene_buffers.opaque_primitves_count, 1, 1);
    }

    pub const DrawPushData = extern struct {
        view_projection_matrix: zm.Mat,
        scene_instances_ptr: vk.DeviceAddress,
        indirect_command_infos_ptr: vk.DeviceAddress,
        material_info_binding: u32,
    };

    fn drawPass(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
        const data: *Data = @ptrCast(@alignCast(build_data.?));

        const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
        const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
        const aspect_ratio: f32 = width_float / height_float;
        const view_matrix = data.camera.transform.getViewMatrix();
        var projection_matrix = data.camera.settings.getProjectionMatrix(aspect_ratio);
        projection_matrix[1][1] *= -1.0;
        const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

        const material_info_buffer = resources.getBuffer(data.material_info_buffer).?;
        const instance_buffer = resources.getBuffer(data.scene_buffers.instance_buffer).?;
        const indirect_count_buffer = resources.getBuffer(data.scene_buffers.indirect_draw_counts_buffer).?;

        command_buffer.bindPipeline(.graphics, data.opaque_draw_pipeline);

        const vertex_buffer = resources.getBuffer(data.vertex_buffer).?;
        const index_buffer = resources.getBuffer(data.index_buffer).?;

        const base_vertex_offset: u64 = 0;
        command_buffer.bindVertexBuffers(0, 1, @ptrCast(&vertex_buffer.handle), @ptrCast(&base_vertex_offset));
        command_buffer.bindIndexBuffer(index_buffer.handle, 0, .uint32);

        const opaque_indirect_cmd_info = resources.getBuffer(data.scene_buffers.opaque_indirect_cmd_info).?;

        const push_data: DrawPushData = .{
            .view_projection_matrix = view_projection_matrix,
            .scene_instances_ptr = instance_buffer.device_address.?,
            .indirect_command_infos_ptr = opaque_indirect_cmd_info.device_address.?,
            .material_info_binding = material_info_buffer.storage_binding.?,
        };
        command_buffer.pushConstants(device.bindless_layout, device.device.all_stage_flags, 0, @sizeOf(DrawPushData), &push_data);

        const indirect_buffer = resources.getBuffer(data.scene_buffers.opaque_indirect_cmd_info).?;

        command_buffer.drawIndexedIndirectCount(
            indirect_buffer.handle,
            0,
            indirect_count_buffer.handle,
            0 * @sizeOf(u32),
            data.scene_buffers.opaque_primitves_count,
            @intCast(@sizeOf(SceneBuffers.DrawIndexedIndirectCommandInfo)),
        );
    }
};
