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

    //Might need to split vert/idx loading up if it possible for either to be zero
    const vertex_size: usize = @intCast(draw_data.total_vtx_count);
    const index_size: usize = @intCast(draw_data.total_idx_count);

    const vertex_size_bytes: usize = vertex_size * @sizeOf(zimgui.DrawVert);
    const index_size_bytes: usize = index_size * @sizeOf(zimgui.DrawIdx);

    //TODO: IDK if I need to copy here but I don't want to risk the possibily that NewFrame() is called before upload callback reads the data
    const vertex_data = try temp_allocator.alloc(zimgui.DrawVert, vertex_size);
    errdefer temp_allocator.free(vertex_data);

    const index_data = try temp_allocator.alloc(zimgui.DrawIdx, index_size);
    errdefer temp_allocator.free(index_data);

    {
        var i_vertex: usize = 0;
        var i_index: usize = 0;

        const cmd_list_count: usize = @intCast(draw_data.cmd_lists.len);

        for (draw_data.cmd_lists.items[0..cmd_list_count]) |cmd| {
            const cmd_vertex_data = cmd.getVertexBuffer();
            const cmd_index_data = cmd.getIndexBuffer();

            std.mem.copyForwards(zimgui.DrawVert, vertex_data[i_vertex..], cmd_vertex_data);
            std.mem.copyForwards(zimgui.DrawIdx, index_data[i_index..], cmd_index_data);

            i_vertex += cmd_vertex_data.len;
            i_index += cmd_index_data.len;
        }
    }

    const vertex_buffer = try render_graph.createTransientBuffer(.{
        .size = vertex_size_bytes,
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
    });
    const index_buffer = try render_graph.createTransientBuffer(.{
        .size = index_size_bytes,
        .usage = .{ .transfer_dst_bit = true, .index_buffer_bit = true },
    });

    const user_datas = try temp_allocator.alloc(SliceData, 2);

    user_datas[0] = .{ .ptr = @ptrCast(vertex_data.ptr), .len = vertex_data.len };
    user_datas[1] = .{ .ptr = @ptrCast(index_data.ptr), .len = index_data.len };

    try render_graph.buffer_upload_passes.append(.{
        .target = vertex_buffer,
        .offset = 0,
        .size = vertex_size_bytes,
        .write_fn = vertexUploadPass,
        .write_data = @ptrCast(&user_datas[0]),
    });

    try render_graph.buffer_upload_passes.append(.{
        .target = index_buffer,
        .offset = 0,
        .size = index_size_bytes,
        .write_fn = indexUploadPass,
        .write_data = @ptrCast(&user_datas[1]),
    });

    var render_pass = try rg.RenderPass.init(temp_allocator, "Imgui Pass");
    try render_pass.addColorAttachment(.{ .texture = target });
    render_pass.addBuildFn(buildCommandBuffer, null);

    try render_graph.render_passes.append(render_pass);
}

const SliceData = struct { ptr: *anyopaque, len: usize };

fn vertexUploadPass(write_data: ?*anyopaque, dst: []u8) usize {
    const data: *SliceData = @alignCast(@ptrCast(write_data));
    const vertex_ptr: [*]const zimgui.DrawVert = @alignCast(@ptrCast(data.ptr));
    const vertex_slice: []const zimgui.DrawVert = vertex_ptr[0..data.len];
    const vertex_bytes: []const u8 = std.mem.sliceAsBytes(vertex_slice);
    std.mem.copyForwards(u8, dst, vertex_bytes);
    return vertex_bytes.len;
}

fn indexUploadPass(write_data: ?*anyopaque, dst: []u8) usize {
    const data: *SliceData = @alignCast(@ptrCast(write_data));
    const index_ptr: [*]const zimgui.DrawIdx = @alignCast(@ptrCast(data.ptr));
    const index_slice: []const zimgui.DrawIdx = index_ptr[0..data.len];
    const index_bytes: []const u8 = std.mem.sliceAsBytes(index_slice);
    std.mem.copyForwards(u8, dst, index_bytes);
    return index_bytes.len;
}

fn buildCommandBuffer(build_data: ?*anyopaque, device: *Device, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = build_data; // autofix
    _ = device; // autofix
    _ = command_buffer; // autofix
    _ = raster_pass_extent; // autofix
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
