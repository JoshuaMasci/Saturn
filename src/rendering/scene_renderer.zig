const std = @import("std");

const zm = @import("zmath");

const saturn = @import("../root.zig");
const Transform = @import("../transform.zig");

const Scene = @import("scene.zig");
const AssetPool = @import("asset_pool.zig");
const Material = @import("material.zig");
const culling = @import("culling.zig");
const utils = @import("utils.zig");

const AssetRegistry = @import("../asset/registry.zig");
const MeshAsset = @import("../asset/mesh.zig");
const ShaderAsset = @import("../asset/shader.zig");

pub const Camera = struct {
    camera: @import("../rendering/camera.zig").Camera,
    transform: Transform,
};

pub const RenderTargetState = struct {
    color_targets: []const saturn.TextureFormat = &.{},
    depth_target: ?saturn.TextureFormat = null,
};

const Self = @This();

gpa: std.mem.Allocator,
device: saturn.DeviceInterface,
registry: *const AssetRegistry,

depth_format: ?saturn.TextureFormat,

legacy: LegacyScenePass,
indirect: IndirectScenePass,

pub fn init(gpa: std.mem.Allocator, device: saturn.DeviceInterface, registry: *const AssetRegistry, formats: RenderTargetState) !Self {
    const legacy: LegacyScenePass = try .init(gpa, device, registry, formats);
    errdefer legacy.deinit(device);

    const indirect: IndirectScenePass = try .init(gpa, device, registry);
    errdefer indirect.deinit(device);

    return .{
        .gpa = gpa,
        .device = device,
        .registry = registry,

        .depth_format = formats.depth_target,
        .legacy = legacy,
        .indirect = indirect,
    };
}

pub fn deinit(self: *Self) void {
    self.legacy.deinit(self.device);
    self.indirect.deinit(self.device);
}

pub fn rebuild(self: *Self, formats: RenderTargetState) saturn.Error!void {
    self.legacy.deinit(self.device);
    self.legacy = try LegacyScenePass.init(self.gpa, self.device, self.registry, formats);
    try self.indirect.rebuild(formats);
}

pub fn addPasses(
    self: *Self,
    tpa: std.mem.Allocator,
    target: saturn.RGTextureHandle,
    render_graph: *saturn.RenderGraph,
    scene: *const Scene,
    camera: *const Camera,
    asset_pool: *const AssetPool,
    settings: *Settings,
) saturn.Error!void {
    self.indirect.addPasses(
        tpa,
        target,
        render_graph,
        scene,
        camera,
        settings,
    ) catch |err| std.log.err("Indirect Build {}", .{err});

    var render_buckets = try scene.createBuckets(tpa, asset_pool);
    render_buckets.depthSort(camera.transform.position);

    const legacy_pass_data = try render_graph.alloc(LegacyPassData, 1);
    legacy_pass_data[0] = .{
        .legacy_pass = &self.legacy,
        .scene = scene,
        .camera = camera,
        .asset_pool = asset_pool,
        .render_buckets = render_buckets,
        .settings = settings,
    };

    const depth_texture = try render_graph.createTransientTexture(.{
        .extent = .{ .relative = target },
        .format = self.depth_format.?,
        .usage = .{
            .attachment = true,
        },
        .memory = .gpu_only,
    });

    _ = try render_graph.addGraphicsPass(
        "Legacy Scene Pass",
        .{
            .color_attachments = &.{
                .{ .texture = target, .clear = .{ 0.0, 0.0, 0.0, 1.0 } },
            },
            .depth_attachment = .{ .texture = depth_texture, .clear = 1.0 },
        },
        legacy_pass_data.ptr,
        legacyGraphicsCallback,
    );
}

pub const Settings = struct {
    culling: bool = true,
    draw_count: usize = 0,
    culled_count: usize = 0,
};

const LegacyPassData = struct {
    legacy_pass: *const LegacyScenePass,
    scene: *const Scene,
    camera: *const Camera,
    asset_pool: *const AssetPool,
    render_buckets: Scene.RenderBuckets,
    settings: *Settings,
};

fn legacyGraphicsCallback(ctx: ?*anyopaque, cmd: saturn.GraphicsCommandEncoder, target_resolution: [2]u32) void {
    const data: *LegacyPassData = @ptrCast(@alignCast(ctx.?));
    data.legacy_pass.render(cmd, data.render_buckets, data.camera, data.asset_pool, target_resolution, data.settings);
}

pub const ClearBufferPass = struct {
    buffer: saturn.RGBufferHandle,
    data: u32,

    pub fn addPass(
        render_graph: *saturn.RenderGraph,
        buffer: saturn.RGBufferHandle,
        data: u32,
    ) saturn.Error!void {
        const ctx = try render_graph.dupe(ClearBufferPass, .{ .buffer = buffer, .data = data });
        const pass = try render_graph.addTransferPass("Buffer Clear Pass", ctx, clearPassCallback);
        try render_graph.addBufferUsage(pass, buffer, .transfer_write);
    }

    fn clearPassCallback(ctx: ?*anyopaque, cmd: saturn.TransferCommandEncoder) void {
        const data: *ClearBufferPass = @ptrCast(@alignCast(ctx));
        const dst: saturn.BufferArg = .from(data.buffer);
        const info = cmd.getBufferInfo(dst).?;
        cmd.writeBuffer(dst, 0, info.size, data.data);
    }
};

const LegacyScenePass = struct {
    const PushConstants = extern struct {
        view_projection_matrix: zm.Mat,
        model_matrix: zm.Mat,
        texture_info_binding: u32,
        material_instance_binding: u32,
        material_index: u32,
    };

    opaque_pipeline: saturn.GraphicsPipelineHandle,
    alpha_mask_pipeline: saturn.GraphicsPipelineHandle,
    alpha_blend_pipeline: saturn.GraphicsPipelineHandle,

    pub fn init(gpa: std.mem.Allocator, device: saturn.DeviceInterface, registry: *const AssetRegistry, formats: RenderTargetState) !LegacyScenePass {
        const vertex_shader = try utils.loadShader(gpa, device, registry, .fromRepoPath("engine", "shaders/glsl/draw_legacy.vert.asset"));
        defer device.destroyShaderModule(vertex_shader);

        const opaque_frag_shader = try utils.loadShader(gpa, device, registry, .fromRepoPath("engine", "shaders/glsl/opaque_legacy.frag.asset"));
        defer device.destroyShaderModule(opaque_frag_shader);

        const alpha_mask_frag_shader = try utils.loadShader(gpa, device, registry, .fromRepoPath("engine", "shaders/glsl/alpha_mask_legacy.frag.asset"));
        defer device.destroyShaderModule(alpha_mask_frag_shader);

        const vertex_bindings = [_]saturn.VertexBinding{
            .{
                .binding = 0,
                .stride = @sizeOf(MeshAsset.Vertex),
                .input_rate = .vertex,
            },
        };

        const vertex_attributes = [_]saturn.VertexAttribute{
            .{
                .binding = 0,
                .location = 0,
                .format = .float3,
                .offset = @offsetOf(MeshAsset.Vertex, "position"),
            },
            .{
                .binding = 0,
                .location = 1,
                .format = .float3,
                .offset = @offsetOf(MeshAsset.Vertex, "normal"),
            },
            .{
                .binding = 0,
                .location = 2,
                .format = .float4,
                .offset = @offsetOf(MeshAsset.Vertex, "tangent"),
            },
            .{
                .binding = 0,
                .location = 3,
                .format = .float2,
                .offset = @offsetOf(MeshAsset.Vertex, "uv0"),
            },
            .{
                .binding = 0,
                .location = 4,
                .format = .float2,
                .offset = @offsetOf(MeshAsset.Vertex, "uv1"),
            },
        };

        const vertex_input_state: saturn.VertexInputState = .{
            .bindings = &vertex_bindings,
            .attributes = &vertex_attributes,
        };

        const raster_state: saturn.RasterizerState = .{
            .fill_mode = .solid,
            .cull_mode = .back,
            .front_face = .counter_clockwise,
            .depth_bias_enable = false,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
        };

        const depth_stencil_state: saturn.DepthStencilState = .{
            .depth_test_enable = true,
            .depth_write_enable = true,
            .depth_compare_op = .less,
        };

        const render_target_info: saturn.RenderTargetState = .{
            .color_targets = try gpa.alloc(saturn.ColorTargetState, formats.color_targets.len),
            .depth_target = formats.depth_target,
        };
        defer gpa.free(render_target_info.color_targets);

        for (render_target_info.color_targets, formats.color_targets) |*target, format| {
            target.* = .{ .format = format };
        }

        const opaque_pipeline = try device.createGraphicsPipeline(&.{
            .name = "Legacy Opaque Pipeline",
            .vertex = vertex_shader,
            .fragment = opaque_frag_shader,
            .vertex_input_state = vertex_input_state,
            .primitive_topology = .triangle_list,
            .raster_state = raster_state,
            .depth_stencil_state = depth_stencil_state,
            .target_info = render_target_info,
        });
        errdefer device.destroyGraphicsPipeline(opaque_pipeline);

        const alpha_mask_pipeline = try device.createGraphicsPipeline(&.{
            .name = "Legacy Alpha Mask Pipeline",
            .vertex = vertex_shader,
            .fragment = alpha_mask_frag_shader,
            .vertex_input_state = vertex_input_state,
            .primitive_topology = .triangle_list,
            .raster_state = raster_state,
            .depth_stencil_state = depth_stencil_state,
            .target_info = render_target_info,
        });
        errdefer device.destroyGraphicsPipeline(alpha_mask_pipeline);

        //Add blending
        for (render_target_info.color_targets) |*target| {
            target.blend = .{
                .color = .{
                    .src = .src_alpha,
                    .dst = .one_minus_src_alpha,
                    .op = .add,
                },
                .alpha = .{
                    .src = .one,
                    .dst = .zero,
                    .op = .add,
                },
            };
        }

        const alpha_blend_pipeline = try device.createGraphicsPipeline(&.{
            .name = "Legacy Alpha Blend Pipeline",
            .vertex = vertex_shader,
            .fragment = opaque_frag_shader,
            .vertex_input_state = vertex_input_state,
            .primitive_topology = .triangle_list,
            .raster_state = raster_state,
            .depth_stencil_state = depth_stencil_state,
            .target_info = render_target_info,
        });
        errdefer device.destroyGraphicsPipeline(alpha_blend_pipeline);

        return .{
            .opaque_pipeline = opaque_pipeline,
            .alpha_mask_pipeline = alpha_mask_pipeline,
            .alpha_blend_pipeline = alpha_blend_pipeline,
        };
    }

    pub fn deinit(self: *const LegacyScenePass, device: saturn.DeviceInterface) void {
        device.destroyGraphicsPipeline(self.opaque_pipeline);
        device.destroyGraphicsPipeline(self.alpha_mask_pipeline);
        device.destroyGraphicsPipeline(self.alpha_blend_pipeline);
    }

    pub fn render(
        self: *const LegacyScenePass,
        cmd: saturn.GraphicsCommandEncoder,
        render_buckets: Scene.RenderBuckets,
        camera: *const Camera,
        asset_pool: *const AssetPool,
        target_resolution: [2]u32,
        settings: *Settings,
    ) void {
        const width_float: f32 = @floatFromInt(target_resolution[0]);
        const height_float: f32 = @floatFromInt(target_resolution[1]);
        const aspect_ratio: f32 = width_float / height_float;

        const view_matrix = camera.transform.getViewMatrix();
        var projection_matrix = camera.camera.getProjectionMatrix(aspect_ratio);
        projection_matrix[1][1] *= -1.0; //TODO: only do this for vulkan
        const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

        const frustum_opt: ?culling.Frustum = if (settings.culling) .fromViewProjectionMatrix(view_projection_matrix) else null;

        cmd.setVertexBuffer(0, .from(asset_pool.mesh_pool.vertex_buffer.buffer), 0);
        cmd.setIndexBuffer(.from(asset_pool.mesh_pool.index_buffer.buffer), .u32, 0);

        const texture_info_binding = asset_pool.texture_pool.info_buffer.storage_binding.?;

        settings.draw_count = 0;
        settings.culled_count = 0;

        drawRenderBucket(
            settings,
            cmd,
            self.opaque_pipeline,
            view_projection_matrix,
            texture_info_binding,
            asset_pool.material_pool.opaque_material.instance_data.storage_binding.?,
            render_buckets.opaque_instances.items,
            frustum_opt,
        );

        drawRenderBucket(
            settings,
            cmd,
            self.alpha_blend_pipeline,
            view_projection_matrix,
            texture_info_binding,
            asset_pool.material_pool.alpha_blend_material.instance_data.storage_binding.?,
            render_buckets.alpha_blend_instances.items,
            frustum_opt,
        );

        drawRenderBucket(
            settings,
            cmd,
            self.alpha_mask_pipeline,
            view_projection_matrix,
            texture_info_binding,
            asset_pool.material_pool.alpha_mask_material.instance_data.storage_binding.?,
            render_buckets.alpha_mask_instances.items,
            frustum_opt,
        );
    }

    fn drawRenderBucket(
        settings: *Settings,
        cmd: saturn.GraphicsCommandEncoder,
        pipeline: saturn.GraphicsPipelineHandle,
        view_projection_matrix: zm.Mat,
        texture_info_binding: u32,
        mat_instance_binding: u32,
        instances: []const Scene.InstanceDrawData,
        frustum_opt: ?culling.Frustum,
    ) void {
        cmd.setPipeline(pipeline);
        for (instances) |instance| {
            if (frustum_opt) |frustum| {
                if (!frustum.intersects(culling.Sphere, instance.culling_sphere)) {
                    settings.culled_count += 1;
                    continue;
                }
            }
            settings.draw_count += 1;

            const push_constants = LegacyScenePass.PushConstants{
                .view_projection_matrix = view_projection_matrix,
                .model_matrix = instance.model_matrix,
                .texture_info_binding = texture_info_binding,
                .material_instance_binding = mat_instance_binding,
                .material_index = instance.material_index,
            };
            cmd.pushConstants(LegacyScenePass.PushConstants, push_constants);

            cmd.drawIndexed(
                instance.draw_data.index_count,
                instance.draw_data.instance_count,
                instance.draw_data.first_index,
                instance.draw_data.vertex_offset,
                instance.draw_data.first_instance,
            );
        }
    }
};

const IndirectScenePass = struct {
    const SceneData = struct {
        mesh_info_buffer: saturn.RGBufferHandle,
        texture_info_buffer: saturn.RGBufferHandle,

        vertex_buffer: saturn.RGBufferHandle,
        index_buffer: saturn.RGBufferHandle,

        instance_buffer: saturn.RGBufferHandle,

        camera: Camera,
    };

    const RenderBucketData = struct {
        material_instance_buffer: saturn.RGBufferHandle,
        primitive_buffer: saturn.RGBufferHandle,
        primitive_count: u32,

        indirect_draw_cmds_buffer: saturn.RGBufferHandle,

        indirect_draw_count_index: u64,
        indirect_draw_counts_buffer: saturn.RGBufferHandle,

        build_pipeline: saturn.ComputePipelineHandle,
        sort_pipeline: ?saturn.ComputePipelineHandle,
        draw_pipeline: saturn.GraphicsPipelineHandle,
    };

    // const BuildData = struct {
    //     camera: Camera,
    //     culling: ?struct {
    //         camera: Camera,
    //         target_texture: saturn.RGTextureHandle, //Needed to calc aspect ratio
    //     },

    //     scene_buffers: SceneBuffers,
    //     primitive_buffer: saturn.RGBufferHandle,

    //     // Write buffer
    //     indirect_draw_cmds_buffer: saturn.RGBufferHandle,

    //     indirect_draw_index: u32,
    //     indirect_draw_counts_buffer: saturn.RGBufferHandle,
    // };

    const DrawIndexedIndirectCommandInfo = extern struct {
        cmd: saturn.IndirectDrawIndexedCommand,
        instance_index: u32,
        material_index: u32,
    };

    indirect_build_pipeline: saturn.ComputePipelineHandle,

    pub fn init(gpa: std.mem.Allocator, device: saturn.DeviceInterface, registry: *const AssetRegistry) !IndirectScenePass {
        const build_shader = try utils.loadShader(gpa, device, registry, .fromRepoPath("engine", "shaders/glsl/build_indirect.comp.asset"));
        defer device.destroyShaderModule(build_shader);

        const indirect_build_pipeline = try device.createComputePipeline(.{ .name = "Build Indirect Comp Pipeline", .shader = build_shader });
        errdefer device.destroyComputePipeline(indirect_build_pipeline);

        return .{
            .indirect_build_pipeline = indirect_build_pipeline,
        };
    }

    pub fn deinit(self: *const IndirectScenePass, device: saturn.DeviceInterface) void {
        device.destroyComputePipeline(self.indirect_build_pipeline);
    }

    pub fn rebuild(self: *IndirectScenePass, formats: RenderTargetState) saturn.Error!void {
        _ = self; // autofix
        _ = formats; // autofix
    }

    pub fn addPasses(
        self: *IndirectScenePass,
        tpa: std.mem.Allocator,
        target: saturn.RGTextureHandle,
        render_graph: *saturn.RenderGraph,
        scene: *const Scene,
        camera: *const Camera,
        settings: *Settings,
    ) saturn.Error!void {
        _ = tpa; // autofix
        _ = target; // autofix
        _ = settings; // autofix

        const indirect_draw_cmds_buffer = try render_graph.createTransientBuffer(.{ .size = @sizeOf(u32) * 16, .usage = .{ .device_address = true, .transfer_dst = true }, .memory = .gpu_only });
        try ClearBufferPass.addPass(render_graph, indirect_draw_cmds_buffer, 0);

        const scene_data: SceneData = .{
            .mesh_info_buffer = try render_graph.importBuffer(scene.asset_pool.mesh_pool.info_buffer.buffer),
            .texture_info_buffer = try render_graph.importBuffer(scene.asset_pool.texture_pool.info_buffer.buffer),

            .vertex_buffer = try render_graph.importBuffer(scene.asset_pool.mesh_pool.vertex_buffer.buffer),
            .index_buffer = try render_graph.importBuffer(scene.asset_pool.mesh_pool.index_buffer.buffer),

            .instance_buffer = try render_graph.importBuffer(scene.gpu_instances.buffer),

            .camera = camera.*,
        };

        //TODO: Round up to the nearest pow2, needed for Bitonic Sort
        const opaque_primitive_count = scene.primtive_instances.opaque_primitives.getCount();

        if (opaque_primitive_count != 0) {
            const opaque_bucket_data: RenderBucketData = .{
                .material_instance_buffer = try render_graph.importBuffer(scene.asset_pool.material_pool.opaque_material.instance_data.buffer),
                .primitive_buffer = try render_graph.importBuffer(scene.primtive_instances.opaque_primitives.buffer),
                .primitive_count = @intCast(opaque_primitive_count),

                .indirect_draw_cmds_buffer = try render_graph.createTransientBuffer(.{ .size = @sizeOf(DrawIndexedIndirectCommandInfo) * opaque_primitive_count, .usage = .{ .device_address = true }, .memory = .gpu_only }),

                .indirect_draw_count_index = 0,
                .indirect_draw_counts_buffer = indirect_draw_cmds_buffer,

                .build_pipeline = self.indirect_build_pipeline,
                .sort_pipeline = null,
                .draw_pipeline = .null_handle,
            };

            try addBuildPass(
                "Build Opaque Indirect Draw Commands",
                render_graph,
                scene_data,
                opaque_bucket_data,
            );
        }
    }

    const IndirectBucketData = struct {
        scene: SceneData,
        bucket: RenderBucketData,
    };

    fn addBuildPass(
        name: []const u8,
        render_graph: *saturn.RenderGraph,
        scene_data: SceneData,
        bucket_data: RenderBucketData,
    ) saturn.Error!void {
        if (bucket_data.primitive_count == 0) {
            return;
        }

        const ctx = try render_graph.dupe(IndirectBucketData, .{ .scene = scene_data, .bucket = bucket_data });
        const build_pass = try render_graph.addComputePass(name, ctx, buildPassCallback);

        //Read
        try render_graph.addBufferUsage(build_pass, scene_data.mesh_info_buffer, .compute_storage_read);
        try render_graph.addBufferUsage(build_pass, scene_data.instance_buffer, .compute_storage_read);
        try render_graph.addBufferUsage(build_pass, bucket_data.primitive_buffer, .compute_storage_read);

        //Write
        try render_graph.addBufferUsage(build_pass, bucket_data.indirect_draw_counts_buffer, .compute_storage_write);
        try render_graph.addBufferUsage(build_pass, bucket_data.indirect_draw_cmds_buffer, .compute_storage_write);
    }

    const BuildPushData = extern struct {
        indirect_draw_counts_ptr: u64,

        mesh_infos_ptr: u64,
        scene_instances_ptr: u64,
        scene_primitives_ptr: u64,

        indirect_command_infos_ptr: u64,

        culling: u32,
        cull_data: GpuCullData,
    };

    fn buildPassCallback(ctx: ?*anyopaque, cmd: saturn.ComputeCommandEncoder) void {
        const data: *IndirectBucketData = @ptrCast(@alignCast(ctx.?));

        const indirect_draw_counts_ptr: u64 = cmd.getBufferInfo(.from(data.bucket.indirect_draw_counts_buffer)).?.device_address.? + (data.bucket.indirect_draw_count_index * @sizeOf(u32));

        const mesh_infos_ptr: u64 = cmd.getBufferInfo(.from(data.scene.mesh_info_buffer)).?.device_address.?;
        const scene_instances_ptr: u64 = cmd.getBufferInfo(.from(data.scene.instance_buffer)).?.device_address.?;
        const scene_primitives_ptr: u64 = cmd.getBufferInfo(.from(data.bucket.primitive_buffer)).?.device_address.?;

        const indirect_command_infos_ptr: u64 = cmd.getBufferInfo(.from(data.bucket.indirect_draw_cmds_buffer)).?.device_address.?;

        //TODO: use indirect compute dispatch
        const primitive_count: u32 = data.bucket.primitive_count;
        const pipeline: saturn.ComputePipelineHandle = data.bucket.build_pipeline;

        cmd.setPipeline(pipeline);
        cmd.pushConstants(BuildPushData, .{
            .indirect_draw_counts_ptr = indirect_draw_counts_ptr,

            .mesh_infos_ptr = mesh_infos_ptr,
            .scene_instances_ptr = scene_instances_ptr,
            .scene_primitives_ptr = scene_primitives_ptr,

            .indirect_command_infos_ptr = indirect_command_infos_ptr,

            .culling = 0,
            .cull_data = undefined,
        });
        cmd.dispatch(primitive_count, 1, 1);
    }
};

pub const GpuCullData = extern struct {
    view_matrix: zm.Mat,
    p00_p11_znear_zfar: zm.Vec,
    frustum: zm.Vec,

    pub fn init(camera: Camera, aspect_ratio: f32) @This() {
        // The following culling code is based on the magic found here: github.com/zeux/niagara
        const view_matrix = camera.transform.getViewMatrix();
        const camera_data = camera.settings.perspective; //Only works for perspective
        const projection_matrix = camera_data.getPerspectiveMatrix(aspect_ratio);
        const projection_t = zm.transpose(projection_matrix);
        const frustum_x = normalizePlane(projection_t[3] + projection_t[0]);
        const frustum_y = normalizePlane(projection_t[3] + projection_t[1]);
        return .{
            .view_matrix = view_matrix,
            .p00_p11_znear_zfar = .{ projection_matrix[0][0], projection_matrix[1][1], camera_data.near, camera_data.far orelse 1000.0 },
            .frustum = .{ frustum_x[0], frustum_x[2], frustum_y[1], frustum_y[2] },
        };
    }

    fn normalizePlane(plane: zm.Vec) zm.Vec {
        return plane / zm.length3(plane);
    }
};
