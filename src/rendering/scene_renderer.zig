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

pub fn init(gpa: std.mem.Allocator, device: saturn.DeviceInterface, registry: *const AssetRegistry, formats: RenderTargetState) !Self {
    const legacy: LegacyScenePass = try .init(gpa, device, registry, formats);
    errdefer legacy.deinit(device);

    return .{
        .gpa = gpa,
        .device = device,
        .registry = registry,

        .depth_format = formats.depth_target,
        .legacy = legacy,
    };
}

pub fn deinit(self: *Self) void {
    self.legacy.deinit(self.device);
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
) saturn.Error!void {
    const depth_texture = try render_graph.createTransientTexture(.{
        .extent = .{ .relative = target },
        .format = self.depth_format.?,
        .usage = .{
            .attachment = true,
        },
        .memory = .gpu_only,
    });

    var render_buckets = try scene.createBuckets(tpa, asset_pool);
    render_buckets.depthSort(camera.transform.position);

    const legacy_pass_data = try render_graph.alloc(LegacyPassData, 1);
    legacy_pass_data[0] = .{
        .legacy_pass = &self.legacy,
        .scene = scene,
        .camera = camera,
        .asset_pool = asset_pool,
        .render_buckets = render_buckets,
    };

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

const LegacyPassData = struct {
    legacy_pass: *const LegacyScenePass,
    scene: *const Scene,
    camera: *const Camera,
    asset_pool: *const AssetPool,
    render_buckets: Scene.RenderBuckets,
};

fn legacyGraphicsCallback(ctx: ?*anyopaque, cmd: saturn.GraphicsCommandEncoder, target_resolution: [2]u32) void {
    const data: *LegacyPassData = @ptrCast(@alignCast(ctx.?));
    data.legacy_pass.render(cmd, data.render_buckets, data.camera, data.asset_pool, target_resolution);
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
    ) void {
        const width_float: f32 = @floatFromInt(target_resolution[0]);
        const height_float: f32 = @floatFromInt(target_resolution[1]);
        const aspect_ratio: f32 = width_float / height_float;

        const view_matrix = camera.transform.getViewMatrix();
        var projection_matrix = camera.camera.getProjectionMatrix(aspect_ratio);
        projection_matrix[1][1] *= -1.0; //TODO: only do this for vulkan
        const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

        const CULLING_ENABLED: bool = true;
        const frustum_opt: ?culling.Frustum = if (CULLING_ENABLED) .fromViewProjectionMatrix(view_projection_matrix) else null;

        cmd.setVertexBuffer(0, .from(asset_pool.mesh_pool.vertex_buffer.buffer), 0);
        cmd.setIndexBuffer(.from(asset_pool.mesh_pool.index_buffer.buffer), .u32, 0);

        const texture_info_binding = asset_pool.texture_pool.info_buffer.storage_binding.?;

        drawRenderBucket(
            cmd,
            self.opaque_pipeline,
            view_projection_matrix,
            texture_info_binding,
            asset_pool.material_pool.opaque_material.instance_data.storage_binding.?,
            render_buckets.opaque_instances.items,
            frustum_opt,
        );

        drawRenderBucket(
            cmd,
            self.alpha_mask_pipeline,
            view_projection_matrix,
            texture_info_binding,
            asset_pool.material_pool.alpha_mask_material.instance_data.storage_binding.?,
            render_buckets.alpha_mask_instances.items,
            frustum_opt,
        );

        drawRenderBucket(
            cmd,
            self.alpha_blend_pipeline,
            view_projection_matrix,
            texture_info_binding,
            asset_pool.material_pool.alpha_blend_material.instance_data.storage_binding.?,
            render_buckets.alpha_blend_instances.items,
            frustum_opt,
        );
    }

    fn drawRenderBucket(
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
                    continue;
                }
            }

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
