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
const Backend = @import("vulkan/backend.zig");
const Image = @import("vulkan/image.zig");
const Mesh = @import("vulkan/mesh.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");
const utils = @import("vulkan/utils.zig");

pub const BuildCommandBufferData = struct {
    self: *Self,
    resources: *const Resources,
    static_mesh_buffer: Backend.BufferHandle,
    material_buffer: Backend.BufferHandle,

    draw_infos_buffer_handle: rg.RenderGraphBufferHandle,
    indirect_info_buffer: rg.RenderGraphBufferHandle,
    indirect_info: []const vk.DrawIndirectCommand,
    indirect_count: u32,

    camera: Camera,
    camera_transform: Transform,
};

const Self = @This();

allocator: std.mem.Allocator,
device: *Backend,

opaque_mesh_pipeline_new: vk.Pipeline,

//Debug Values
enable_rendering: bool = false,
enable_indirect: bool = false,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    device: *Backend,
    color_format: vk.Format,
    depth_format: vk.Format,
    pipeline_layout: vk.PipelineLayout,
) !Self {
    const vertex_shader_new = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/static_mesh_new.vert.asset"));
    defer device.device.proxy.destroyShaderModule(vertex_shader_new, null);

    const opaque_fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/opaque.frag.asset"));
    defer device.device.proxy.destroyShaderModule(opaque_fragment_shader, null);

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

    return .{
        .allocator = allocator,
        .device = device,
        .opaque_mesh_pipeline_new = opaque_mesh_pipeline_new,
    };
}

pub fn deinit(self: *Self) void {
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
    var draw_infos = try std.ArrayList(DrawInfo).initCapacity(temp_allocator, scene.static_meshes.items.len);
    var indirect_info = try std.ArrayList(vk.DrawIndirectCommand).initCapacity(temp_allocator, scene.static_meshes.items.len);

    for (scene.static_meshes.items) |static_mesh| {
        const model_matirx = static_mesh.transform.getModelMatrix();

        if (resources.static_mesh_map.get(static_mesh.component.mesh)) |entry| {
            const materials = static_mesh.component.materials.constSlice();
            for (entry.mesh.primitives, materials, 0..) |primitive, material, primitive_index| {
                if (resources.material_map.get(material)) |mat_entry| {
                    if (mat_entry.material.alpha_mode != .alpha_opaque) {
                        continue;
                    }
                    const instance: u32 = @intCast(draw_infos.items.len);
                    draw_infos.append(temp_allocator, .{
                        .model_matrix = model_matirx,
                        .mesh_index = entry.buffer_index.?,
                        .primitive_index = @intCast(primitive_index),
                        .material_index = mat_entry.buffer_index.?,
                    }) catch continue;

                    indirect_info.append(temp_allocator, .{
                        .first_instance = instance,
                        .instance_count = 1,
                        .first_vertex = 0,
                        .vertex_count = primitive.index_count,
                    }) catch {
                        _ = draw_infos.pop();
                        continue;
                    };
                }
            }
        }
    }

    const draw_infos_buffer = try render_graph.uploadSliceToBuffer(DrawInfo, .{ .storage_buffer_bit = true }, draw_infos.items);
    const indirect_info_buffer = try render_graph.uploadSliceToBuffer(vk.DrawIndirectCommand, .{ .indirect_buffer_bit = true }, indirect_info.items);

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
        .draw_infos_buffer_handle = draw_infos_buffer,
        .indirect_info_buffer = indirect_info_buffer,
        .indirect_info = indirect_info.items,
        .indirect_count = @intCast(indirect_info.items.len),
        .camera = camera,
        .camera_transform = camera_transform,
    };
    render_pass.addBuildFn(buildCommandBuffer, scene_build_data);

    try render_graph.render_passes.append(render_graph.allocator, render_pass);
}

pub fn buildCommandBuffer(build_data: ?*anyopaque, device: *Backend, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    const data: *BuildCommandBufferData = @ptrCast(@alignCast(build_data.?));
    const self = data.self;

    const static_mesh_buffer = device.buffers.get(data.static_mesh_buffer).?;
    const material_buffer = device.buffers.get(data.material_buffer).?;
    const draw_infos_buffer = resources.buffers[data.draw_infos_buffer_handle.index];
    const indirect_info_buffer = resources.buffers[data.indirect_info_buffer.index];

    const width_float: f32 = @floatFromInt(raster_pass_extent.?.width);
    const height_float: f32 = @floatFromInt(raster_pass_extent.?.height);
    const aspect_ratio: f32 = width_float / height_float;
    const view_matrix = data.camera_transform.getViewMatrix();
    var projection_matrix = data.camera.getProjectionMatrix(aspect_ratio);
    projection_matrix[1][1] *= -1.0;
    const view_projection_matrix = zm.mul(view_matrix, projection_matrix);

    // const frustum: culling.Frustum = data.camera.getFrustum(aspect_ratio, data.camera_transform);
    // _ = frustum; // autofix

    {
        command_buffer.bindPipeline(.graphics, self.opaque_mesh_pipeline_new);
        const push_data = PushData{
            .view_projection_matrix = view_projection_matrix,
            .static_mesh_binding = static_mesh_buffer.storage_binding.?.index,
            .material_binding = material_buffer.storage_binding.?.index,
            .draw_info_binding = draw_infos_buffer.storage_binding.?,
        };
        command_buffer.pushConstants(device.bindless_layout, .{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true }, 0, @sizeOf(PushData), &push_data);
        if (self.enable_rendering) {
            if (self.enable_indirect) {
                command_buffer.drawIndirect(indirect_info_buffer.handle, 0, data.indirect_count, @sizeOf(vk.DrawIndirectCommand));
            } else {
                for (data.indirect_info) |info| {
                    command_buffer.draw(info.vertex_count, info.instance_count, info.first_vertex, info.first_instance);
                }
            }
        }
    }
}

const PushData = extern struct {
    view_projection_matrix: zm.Mat,
    static_mesh_binding: u32,
    material_binding: u32,
    draw_info_binding: u32,
};

const DrawInfo = extern struct {
    model_matrix: zm.Mat,
    mesh_index: u32,
    primitive_index: u32,
    material_index: u32,
    pad: u32 = 0,
};
