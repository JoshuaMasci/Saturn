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

pipeline_layout: vk.PipelineLayout,
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

    // const font_data = zimgui.io.getFontsTextDataAsRgba32();
    // const data_len: usize = @intCast(font_data.width * font_data.height);

    // const font_texture = try device.createImageWithData(
    //     .{ @intCast(font_data.width), @intCast(font_data.height) },
    //     .r8g8b8a8_unorm,
    //     .{ .sampled_bit = true, .transfer_dst_bit = true },
    //     std.mem.sliceAsBytes(font_data.pixels.?[0..data_len]),
    // );

    const font_texture = try device.createImageWithData(
        .{ 1, 1 },
        .r8g8b8a8_unorm,
        .{ .sampled_bit = true, .transfer_dst_bit = true },
        &.{ 0, 0, 0, 1 },
    );

    return .{
        .allocator = allocator,
        .device = device,
        .pipeline_layout = pipeline_layout,
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
    _ = temp_allocator; // autofix
    _ = target; // autofix
    _ = render_graph; // autofix
    return;

    // zimgui.render();
    // const draw_data = zimgui.getDrawData();

    // const framebuffer_size_f: [2]f32 = .{ draw_data.display_size[0] * draw_data.framebuffer_scale[0], draw_data.display_size[1] * draw_data.framebuffer_scale[1] };
    // if (framebuffer_size_f[0] <= 0 or framebuffer_size_f[1] <= 0) {
    //     return;
    // }

    // if (draw_data.cmd_lists_count == 0) {
    //     return;
    // }

    // //Might need to split vert/idx loading up if it possible for either to be zero
    // const vertex_size: usize = @intCast(draw_data.total_vtx_count);
    // const index_size: usize = @intCast(draw_data.total_idx_count);

    // const vertex_size_bytes: usize = vertex_size * @sizeOf(zimgui.DrawVert);
    // const index_size_bytes: usize = index_size * @sizeOf(zimgui.DrawIdx);

    // //TODO: IDK if I need to copy here but I don't want to risk the possibily that NewFrame() is called before upload callback reads the data
    // const vertex_data = try temp_allocator.alloc(zimgui.DrawVert, vertex_size);
    // errdefer temp_allocator.free(vertex_data);

    // const index_data = try temp_allocator.alloc(zimgui.DrawIdx, index_size);
    // errdefer temp_allocator.free(index_data);

    // {
    //     var i_vertex: usize = 0;
    //     var i_index: usize = 0;

    //     const cmd_list_count: usize = @intCast(draw_data.cmd_lists.len);

    //     for (draw_data.cmd_lists.items[0..cmd_list_count]) |cmd| {
    //         const cmd_vertex_data = cmd.getVertexBuffer();
    //         const cmd_index_data = cmd.getIndexBuffer();

    //         std.mem.copyForwards(zimgui.DrawVert, vertex_data[i_vertex..], cmd_vertex_data);
    //         std.mem.copyForwards(zimgui.DrawIdx, index_data[i_index..], cmd_index_data);

    //         i_vertex += cmd_vertex_data.len;
    //         i_index += cmd_index_data.len;
    //     }
    // }

    // const vertex_buffer = try render_graph.createTransientBuffer(.{
    //     .size = vertex_size_bytes,
    //     .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
    // });
    // const index_buffer = try render_graph.createTransientBuffer(.{
    //     .size = index_size_bytes,
    //     .usage = .{ .transfer_dst_bit = true, .index_buffer_bit = true },
    // });

    // const user_datas = try temp_allocator.alloc(SliceData, 2);
    // errdefer temp_allocator.free(user_datas);

    // user_datas[0] = .{ .ptr = @ptrCast(vertex_data.ptr), .len = vertex_data.len };
    // user_datas[1] = .{ .ptr = @ptrCast(index_data.ptr), .len = index_data.len };

    // try render_graph.buffer_upload_passes.append(.{
    //     .target = vertex_buffer,
    //     .offset = 0,
    //     .size = vertex_size_bytes,
    //     .write_fn = vertexUploadPass,
    //     .write_data = @ptrCast(&user_datas[0]),
    // });

    // try render_graph.buffer_upload_passes.append(.{
    //     .target = index_buffer,
    //     .offset = 0,
    //     .size = index_size_bytes,
    //     .write_fn = indexUploadPass,
    //     .write_data = @ptrCast(&user_datas[1]),
    // });

    // const draw_commands = try temp_allocator.alloc(?DrawCommand, @intCast(draw_data.cmd_lists_count));
    // errdefer temp_allocator.free(draw_commands);
    // @memset(draw_commands, null);

    // const clip_off = draw_data.display_pos;
    // const clip_scale = draw_data.framebuffer_scale;

    // var global_vtx_offset: i32 = 0;
    // var global_idx_offset: u32 = 0;
    // for (draw_commands, draw_data.cmd_lists.items[0..draw_commands.len]) |*draw_command, cmd| {
    //     const min_clip = cmd.getClipRectMin();
    //     const max_clip = cmd.getClipRectMax();

    //     const clip_min = [2]f32{
    //         (min_clip[0] - clip_off[0]) * clip_scale[0],
    //         (min_clip[1] - clip_off[1]) * clip_scale[1],
    //     };
    //     const clip_max = [2]f32{
    //         (max_clip[0] - clip_off[0]) * clip_scale[0],
    //         (max_clip[1] - clip_off[1]) * clip_scale[1],
    //     };

    //     var clamped_min = clip_min;
    //     var clamped_max = clip_max;

    //     if (clamped_min[0] < 0.0) clamped_min[0] = 0.0;
    //     if (clamped_min[1] < 0.0) clamped_min[1] = 0.0;
    //     if (clamped_max[0] > framebuffer_size_f[0]) clamped_max[0] = framebuffer_size_f[0];
    //     if (clamped_max[1] > framebuffer_size_f[1]) clamped_max[1] = framebuffer_size_f[1];

    //     if (clamped_max[0] <= clamped_min[0] or clamped_max[1] <= clamped_min[1]) {
    //         continue;
    //     }

    //     const scissor = vk.Rect2D{
    //         .offset = .{
    //             .x = @intFromFloat(clamped_min[0]),
    //             .y = @intFromFloat(clamped_min[1]),
    //         },
    //         .extent = .{
    //             .width = @intFromFloat(clamped_max[0] - clamped_min[0]),
    //             .height = @intFromFloat(clamped_max[1] - clamped_min[1]),
    //         },
    //     };

    //     draw_command.* = .{
    //         .scissor = scissor,
    //         .texture_id = 0,
    //         .index_count = @intCast(cmd.getIndexBufferLength()),
    //         .first_index = cmd.getCurrentIndex() + global_idx_offset,
    //         .vertex_offset = global_vtx_offset,
    //     };

    //     global_vtx_offset += cmd.getVertexBufferLength();
    //     global_idx_offset += @intCast(cmd.getIndexBufferLength());
    // }

    // var render_pass = try rg.RenderPass.init(temp_allocator, "Imgui Pass");
    // try render_pass.addColorAttachment(.{ .texture = target });

    // const build_data = try temp_allocator.create(BuildData);
    // errdefer temp_allocator.destroy(build_data);

    // build_data.* = .{
    //     .layout = self.pipeline_layout,
    //     .pipeline = self.pipeline,

    //     .display_size = draw_data.display_size,
    //     .display_pos = draw_data.display_pos,

    //     .vertex_buffer_handle = vertex_buffer,
    //     .index_buffer_handle = index_buffer,
    //     .font_texture = try render_graph.importTexture(self.font_texture),
    //     .draw_commands = draw_commands,
    // };

    // render_pass.addBuildFn(buildCommandBuffer, build_data);

    // try render_graph.render_passes.append(render_pass);
}

const SliceData = struct { ptr: *anyopaque, len: usize };

const BuildData = struct {
    layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,
    display_size: [2]f32,
    display_pos: [2]f32,
    vertex_buffer_handle: rg.RenderGraphBufferHandle,
    index_buffer_handle: rg.RenderGraphBufferHandle,
    font_texture: rg.RenderGraphTextureHandle,
    draw_commands: []const ?DrawCommand,
};

const DrawCommand = struct {
    scissor: vk.Rect2D,
    texture_id: u32,
    index_count: u32,
    first_index: u32,
    vertex_offset: i32,
};

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

fn buildCommandBuffer(build_data: ?*anyopaque, device: *Device, resources: rg.Resources, command_buffer: vk.CommandBufferProxy, raster_pass_extent: ?vk.Extent2D) void {
    _ = device; // autofix
    _ = raster_pass_extent; // autofix

    const data: *const BuildData = @alignCast(@ptrCast(build_data));

    const vertex_buffer = resources.buffers[data.vertex_buffer_handle.buffer_index];
    const index_buffer = resources.buffers[data.index_buffer_handle.buffer_index];

    const vertex_buffers: []const vk.Buffer = &.{vertex_buffer.handle};
    const vertex_offsets: []const vk.DeviceSize = &.{0};

    command_buffer.bindPipeline(.graphics, data.pipeline);

    const scale = [2]f32{
        2.0 / data.display_size[0],
        2.0 / data.display_size[1],
    };
    const translate = [2]f32{
        -1.0 - data.display_pos[0] * scale[0],
        -1.0 - data.display_pos[1] * scale[1],
    };
    const push_data: [4]f32 = .{
        scale[0],     scale[1],
        translate[0], scale[1],
    };

    const AllStages = vk.ShaderStageFlags{ .vertex_bit = true, .fragment_bit = true, .compute_bit = true };
    command_buffer.pushConstants(data.layout, AllStages, 0, @sizeOf([4]f32), &push_data);

    command_buffer.bindVertexBuffers(0, @intCast(vertex_buffers.len), vertex_buffers.ptr, vertex_offsets.ptr);
    command_buffer.bindIndexBuffer(index_buffer.handle, 0, if (@sizeOf(zimgui.DrawIdx) == 2) .uint16 else .uint32);

    for (data.draw_commands) |draw_command_opt| {
        if (draw_command_opt) |draw_command| {
            command_buffer.setScissor(0, 1, @ptrCast(&draw_command.scissor));

            command_buffer.drawIndexed(draw_command.index_count, 1, draw_command.first_index, draw_command.vertex_offset, 0);
        }
    }
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
