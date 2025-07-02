const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const ShaderAsset = @import("../asset/shader.zig");
const ShaderAssetHandle = ShaderAsset.Registry.Handle;
const global = @import("../global.zig");
const c = @import("../platform/sdl3.zig").c;
const Window = @import("../platform/sdl3.zig").Window;
const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;
const Device = @import("vulkan/device.zig");
const Mesh = @import("vulkan/mesh.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");
const utils = @import("vulkan/utils.zig");

pub const BuildCommandBufferData = struct {
    self: *const Self,
    camera: Camera,
    camera_transform: Transform,
};

const Self = @This();

allocator: std.mem.Allocator,
device: *Device,

solid_mesh_graphics_pipeline: vk.Pipeline,
wireframe_mesh_graphics_pipeline: vk.Pipeline,

//meshes: std.AutoArrayHashMap(physics.MeshPrimitive, Mesh),

pub fn init(allocator: std.mem.Allocator, device: *Device, color_format: vk.Format, pipeline_layout: vk.PipelineLayout) !Self {
    _ = color_format; // autofix
    _ = pipeline_layout; // autofix
    const vertex_shader = try utils.loadGraphicsShader(allocator, device.device.proxy, ShaderAssetHandle.fromRepoPath("engine:shaders/vulkan/physics_mesh.vert.shader").?);
    defer device.device.proxy.destroyShaderModule(vertex_shader, null);

    const fragment_shader = try utils.loadGraphicsShader(allocator, device.device.proxy, ShaderAssetHandle.fromRepoPath("engine:shaders/vulkan/physics_mesh.frag.shader").?);
    defer device.device.proxy.destroyShaderModule(fragment_shader, null);

    return .{
        .allocator = allocator,
        .device = device,
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.wireframe_mesh_graphics_pipeline, null);
    self.device.device.proxy.destroyPipeline(self.solid_mesh_graphics_pipeline, null);
}

pub fn buildCommandBuffer(build_data: ?*anyopaque, device: *Device, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = device; // autofix
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
    _ = view_projection_matrix; // autofix

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
}
