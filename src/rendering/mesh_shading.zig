const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const Device = @import("vulkan/device.zig");
const Image = @import("vulkan/image.zig");
const Mesh = @import("vulkan/mesh.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");
const utils = @import("vulkan/utils.zig");

pub const BuildCommandBufferData = struct {
    self: *Self,
};

const Self = @This();

enabled: bool = false,
allocator: std.mem.Allocator,
device: *Device,

triangle_pipeline: vk.Pipeline,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    device: *Device,
    color_format: vk.Format,
    pipeline_layout: vk.PipelineLayout,
) !Self {
    var triangle_pipeline: vk.Pipeline = .null_handle;

    //TODO: check device support
    if (device.device.physical_device.info.extensions.mesh_shader_support) {
        const mesh_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/triangle.mesh.asset"));
        defer device.device.proxy.destroyShaderModule(mesh_shader, null);

        const fragment_shader = try utils.loadGraphicsShader(allocator, registry, device.device.proxy, .fromRepoPath("engine", "shaders/vulkan/triangle.frag.asset"));
        defer device.device.proxy.destroyShaderModule(fragment_shader, null);

        triangle_pipeline = try Pipeline.createMeshShaderPipeline(
            device.device.proxy,
            pipeline_layout,
            .{
                .color_format = color_format,
                .cull_mode = .{ .back_bit = true },
            },
            null,
            mesh_shader,
            fragment_shader,
        );
    }

    return .{
        .allocator = allocator,
        .device = device,
        .triangle_pipeline = triangle_pipeline,
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.triangle_pipeline, null);
}

pub fn createRenderPass(
    self: *Self,
    temp_allocator: std.mem.Allocator,
    color_target: rg.RenderGraphTextureHandle,
    render_graph: *rg.RenderGraph,
) !void {
    if (self.triangle_pipeline == .null_handle or !self.enabled) {
        return;
    }

    var render_pass = try rg.RenderPass.init(temp_allocator, "Mesh Shading Pass");
    try render_pass.addColorAttachment(.{
        .texture = color_target,
        .clear = null,
        .store = true,
    });

    const scene_build_data = try temp_allocator.create(BuildCommandBufferData);
    scene_build_data.* = .{
        .self = self,
    };
    render_pass.addBuildFn(buildCommandBuffer, scene_build_data);

    try render_graph.render_passes.append(render_graph.allocator, render_pass);
}

pub fn buildCommandBuffer(build_data: ?*anyopaque, device: *Device, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = device; // autofix
    _ = resources; // autofix
    _ = raster_pass_extent; // autofix

    const data: *BuildCommandBufferData = @ptrCast(@alignCast(build_data.?));
    const self = data.self;

    command_buffer.bindPipeline(.graphics, self.triangle_pipeline);
    command_buffer.drawMeshTasksEXT(1, 1, 1);
}
