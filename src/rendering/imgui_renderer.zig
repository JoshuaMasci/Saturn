const std = @import("std");
const vk = @import("vulkan");
const zimgui = @import("zimgui");

const global = @import("../global.zig");
const Device = @import("vulkan/device.zig");
const ShaderAsset = @import("../asset/shader.zig");
const ShaderAssetHandle = ShaderAsset.Registry.Handle;
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

    var render_pass = try rg.RenderPass.init(temp_allocator, "Imgui Pass");
    try render_pass.addColorAttachment(.{ .texture = target });
    try render_graph.render_passes.append(render_pass);
}

pub fn buildCommandBuffer(device: *Device, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D, user_data: ?*anyopaque) void {
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
