const std = @import("std");

const vk = @import("vulkan");
const zimgui = @import("zimgui");

const ShaderAsset = @import("../asset/shader.zig");
const ShaderAssetHandle = ShaderAsset.Registry.Handle;
const global = @import("../global.zig");
const Device = @import("vulkan/device.zig");
const Pipeline = @import("vulkan/pipeline.zig");
const rg = @import("vulkan/render_graph.zig");

const Self = @This();

allocator: std.mem.Allocator,
device: *Device,

pipeline: vk.Pipeline,
font_texture: Device.ImageHandle,

pub fn init(allocator: std.mem.Allocator, device: *Device, color_format: vk.Format, pipeline_layout: vk.PipelineLayout) !Self {
    const vertex_shader = try loadGraphicsShader(allocator, device.device.proxy, ShaderAssetHandle.fromRepoPath("engine:shaders/vulkan/imgui.vert.shader").?);
    defer device.device.proxy.destroyShaderModule(vertex_shader, null);

    const fragment_shader = try loadGraphicsShader(allocator, device.device.proxy, ShaderAssetHandle.fromRepoPath("engine:shaders/vulkan/imgui.frag.shader").?);
    defer device.device.proxy.destroyShaderModule(fragment_shader, null);

    const pipeline = try Pipeline.createGraphicsPipeline(
        allocator,
        device.device.proxy,
        pipeline_layout,
        .{
            .color_format = color_format,
            .enable_depth_test = false,
            .enable_depth_write = false,
            .cull_mode = .{},
        },
        vertex_shader,
        fragment_shader,
    );

    const font_data = zimgui.io.getFontsTextDataAsRgba32();
    const data_len: usize = @intCast(font_data.width * font_data.height);

    const font_texture = try device.createImageWithData(
        .{ @intCast(font_data.width), @intCast(font_data.height) },
        .r8g8b8a8_unorm,
        .{ .sampled_bit = true, .transfer_dst_bit = true },
        std.mem.sliceAsBytes(font_data.pixels.?[0..data_len]),
    );

    return .{
        .allocator = allocator,
        .device = device,
        .pipeline = pipeline,
        .font_texture = font_texture,
    };
}

pub fn deinit(self: *Self) void {
    self.device.device.proxy.destroyPipeline(self.pipeline, null);
    self.device.destroyImage(self.font_texture);
}

pub fn createRenderPass(self: *Self, temp_allocator: std.mem.Allocator, target: rg.RenderGraphTextureHandle, render_graph: *rg.RenderGraph) !void {
    _ = self; // autofix

    zimgui.render();
    const draw_data = zimgui.getDrawData();

    if (draw_data.cmd_lists_count == 0) {
        return;
    }

    const vertex_size_bytes: usize = @as(usize, @intCast(draw_data.total_vtx_count)) * @sizeOf(zimgui.DrawVert);
    const index_size_bytes: usize = @as(usize, @intCast(draw_data.total_idx_count)) * @sizeOf(zimgui.DrawIdx);

    const vertex_buffer = try render_graph.createTransientBuffer(.{
        .size = vertex_size_bytes,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
    });
    const index_buffer = try render_graph.createTransientBuffer(.{
        .size = index_size_bytes,
        .usage = .{ .transfer_dst_bit = true, .index_buffer_bit = true },
    });

    try render_graph.upload_passes.append(.{
        .target = vertex_buffer,
        .offset = 0,
        .size = vertex_size_bytes,
        .data_fn = vertexUploadPass,
        .user_data = null,
    });

    try render_graph.upload_passes.append(.{
        .target = index_buffer,
        .offset = 0,
        .size = index_size_bytes,
        .data_fn = indexUploadPass,
        .user_data = null,
    });

    var render_pass = try rg.RenderPass.init(temp_allocator, "Imgui Pass");
    try render_pass.addColorAttachment(.{ .texture = target });
    try render_graph.render_passes.append(render_pass);
}

fn vertexUploadPass(dst: []u8, user_data: ?*anyopaque) usize {
    _ = dst; // autofix
    _ = user_data; // autofix
    return 0;
}

fn indexUploadPass(dst: []u8, user_data: ?*anyopaque) usize {
    _ = dst; // autofix
    _ = user_data; // autofix
    return 0;
}

fn buildCommandBuffer(device: *Device, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D, user_data: ?*anyopaque) void {
    _ = device; // autofix
    _ = command_buffer; // autofix
    _ = raster_pass_extent; // autofix
    _ = user_data; // autofix
}

fn loadGraphicsShader(allocator: std.mem.Allocator, device: vk.DeviceProxy, handle: ShaderAssetHandle) !vk.ShaderModule {
    var shader = try global.assets.shaders.loadAsset(allocator, handle);
    defer shader.deinit(allocator);

    if (shader.target != .vulkan) {
        return error.InvalidShaderTarget;
    }

    return try device.createShaderModule(&.{
        .flags = .{},
        .code_size = shader.spirv_code.len * @sizeOf(u32), //Code size is in bytes, despite the p_code being a u32ptr
        .p_code = @alignCast(@ptrCast(shader.spirv_code.ptr)),
    }, null);
}
