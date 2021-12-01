usingnamespace @import("core.zig");
const glfw = @import("glfw");

const vk = @import("vulkan");
usingnamespace @import("vulkan/device.zig");
usingnamespace @import("vulkan/buffer.zig");
usingnamespace @import("vulkan/image.zig");

const TransferQueue = @import("transfer_queue.zig").TransferQueue;
const Input = @import("input.zig").Input;

const resources = @import("resources");

pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
});

const ALL_SHADER_STAGES = vk.ShaderStageFlags{
    .vertex_bit = true,
    .tessellation_control_bit = true,
    .tessellation_evaluation_bit = true,
    .geometry_bit = true,
    .fragment_bit = true,
    .compute_bit = true,
    .task_bit_nv = true,
    .mesh_bit_nv = true,
    .raygen_bit_khr = true,
    .any_hit_bit_khr = true,
    .closest_hit_bit_khr = true,
    .miss_bit_khr = true,
    .intersection_bit_khr = true,
    .callable_bit_khr = true,
};

const SHADER_STAGES = vk.ShaderStageFlags{
    .vertex_bit = true,
    .fragment_bit = true,
};

pub const Layer = struct {
    const Self = @This();

    allocator: *Allocator,
    context: *c.ImGuiContext,
    io: *c.ImGuiIO,

    device: Device,
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,

    freed_buffers: std.ArrayList(Buffer),

    texture_atlas: Image,
    texture_sampler: vk.Sampler,

    pub fn init(allocator: *Allocator, device: Device, transfer_queue: *TransferQueue, render_pass: vk.RenderPass, descriptor_set_layouts: []vk.DescriptorSetLayout) !Self {
        var context = c.igCreateContext(null);

        var io: *c.ImGuiIO = c.igGetIO();
        io.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
        io.DeltaTime = 1.0 / 60.0;
        c.igStyleColorsDark(null);

        var pixels: ?[*]u8 = undefined;
        var width: i32 = undefined;
        var height: i32 = undefined;
        var bytes: i32 = 0;

        c.ImFontAtlas_GetTexDataAsRGBA32(io.Fonts, @ptrCast([*c][*c]u8, &pixels), &width, &height, &bytes);

        //TODO: init texture
        var texture_atlas = try Image.init(
            device,
            .r8g8b8a8_unorm,
            .{
                .width = @intCast(u32, width),
                .height = @intCast(u32, height),
            },
            .{ .device_local_bit = true },
        );
        try texture_atlas.createImageView();

        if (pixels) |pixel_data| {
            var pixel_slice: []u8 = undefined;
            pixel_slice.ptr = pixel_data;
            pixel_slice.len = @intCast(usize, width * height * bytes);
            transfer_queue.copyToImage(texture_atlas, u8, pixel_slice);
        }

        var texture_sampler = try device.dispatch.createSampler(
            device.handle,
            .{
                .flags = .{},
                .mag_filter = .linear,
                .min_filter = .linear,
                .mipmap_mode = .linear,
                .address_mode_u = .clamp_to_border,
                .address_mode_v = .clamp_to_border,
                .address_mode_w = .clamp_to_border,
                .mip_lod_bias = 0.0,
                .anisotropy_enable = vk.FALSE,
                .max_anisotropy = 0.0,
                .compare_enable = vk.FALSE,
                .compare_op = .always,
                .min_lod = 0.0,
                .max_lod = 0.0,
                .border_color = .float_transparent_black,
                .unnormalized_coordinates = vk.FALSE,
            },
            null,
        );

        var push_constant_range = vk.PushConstantRange{
            .stage_flags = SHADER_STAGES,
            .offset = 0,
            .size = 128,
        };

        var pipeline_layout = try device.dispatch.createPipelineLayout(device.handle, .{
            .flags = .{},
            .set_layout_count = @intCast(u32, descriptor_set_layouts.len),
            .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, descriptor_set_layouts.ptr),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, &push_constant_range),
        }, null);

        var pipeline = try device.createPipeline(
            pipeline_layout,
            render_pass,
            &resources.imgui_vert,
            &resources.imgui_frag,
            &ImguiVertex.binding_description,
            &ImguiVertex.attribute_description,
            &.{
                .cull_mode = .{},
                .blend_enable = true,
                .src_color_blend_factor = .src_alpha,
                .dst_color_blend_factor = .one_minus_src_alpha,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .src_alpha,
                .dst_alpha_blend_factor = .one_minus_src_alpha,
                .alpha_blend_op = .add,
            },
        );

        var freed_buffers = std.ArrayList(Buffer).init(allocator);

        return Self{
            .allocator = allocator,
            .context = context,
            .io = io,
            .device = device,
            .pipeline = pipeline,
            .pipeline_layout = pipeline_layout,
            .freed_buffers = freed_buffers,
            .texture_atlas = texture_atlas,
            .texture_sampler = texture_sampler,
        };
    }

    pub fn deinit(self: Self) void {
        self.texture_atlas.deinit();

        self.device.dispatch.destroySampler(self.device.handle, self.texture_sampler, null);

        for (self.freed_buffers.items) |buffer| {
            buffer.deinit();
        }
        self.freed_buffers.deinit();

        self.device.dispatch.destroyPipeline(self.device.handle, self.pipeline, null);
        self.device.dispatch.destroyPipelineLayout(self.device.handle, self.pipeline_layout, null);
        c.igDestroyContext(self.context);
    }

    pub fn update(self: Self, window: glfw.Window, input: *Input) void {
        //Window size update

        var size = window.getSize() catch |err| {
            std.log.err("Failed to get window size, can't use imgui", .{});
            return;
        };

        self.io.DisplaySize = c.ImVec2{
            .x = @intToFloat(f32, size.width),
            .y = @intToFloat(f32, size.height),
        };

        if (input.getMousePos()) |mouse_pos| {
            self.io.MousePos = c.ImVec2{
                .x = mouse_pos[0],
                .y = mouse_pos[1],
            };
        }

        self.io.MouseDown[0] = input.getMouseDown(glfw.mouse_button.MouseButton.left);
        self.io.MouseDown[1] = input.getMouseDown(glfw.mouse_button.MouseButton.right);
        self.io.MouseDown[2] = input.getMouseDown(glfw.mouse_button.MouseButton.middle);
        self.io.MouseDown[3] = input.getMouseDown(glfw.mouse_button.MouseButton.four);
        self.io.MouseDown[4] = input.getMouseDown(glfw.mouse_button.MouseButton.five);
    }

    pub fn beginFrame(self: *Self) void {
        for (self.freed_buffers.items) |buffer| {
            buffer.deinit();
        }
        self.freed_buffers.clearRetainingCapacity();

        c.igNewFrame();
    }

    pub fn endFrame(self: *Self, command_buffer: vk.CommandBuffer, descriptor_sets: []vk.DescriptorSet) !void {
        var open = true;
        c.igShowDemoWindow(&open);

        c.igEndFrame();
        c.igRender();

        var draw_data: *c.ImDrawData = c.igGetDrawData();

        var size_x = draw_data.DisplaySize.x * draw_data.FramebufferScale.x;
        var size_y = draw_data.DisplaySize.y * draw_data.FramebufferScale.y;
        if (size_x <= 0 or size_y <= 0) {
            return;
        }

        self.device.dispatch.cmdBindDescriptorSets(
            command_buffer,
            .graphics,
            self.pipeline_layout,
            0,
            @intCast(u32, descriptor_sets.len),
            @ptrCast([*]const vk.DescriptorSet, descriptor_sets.ptr),
            0,
            undefined,
        );

        self.device.dispatch.cmdBindPipeline(command_buffer, .graphics, self.pipeline);
        {
            var push_data: [4]f32 = undefined;

            //Scale
            push_data[0] = 2.0 / draw_data.DisplaySize.x;
            push_data[1] = 2.0 / draw_data.DisplaySize.y;

            //Translate
            push_data[2] = -1.0 - (draw_data.DisplayPos.x * push_data[0]);
            push_data[3] = -1.0 - (draw_data.DisplayPos.y * push_data[1]);

            self.device.dispatch.cmdPushConstants(command_buffer, self.pipeline_layout, SHADER_STAGES, 0, @sizeOf(@TypeOf(push_data)), &push_data);

            var clip_offset = draw_data.DisplayPos;
            var clip_scale = draw_data.FramebufferScale;

            var i: u32 = 0;
            while (i < draw_data.CmdListsCount) : (i += 1) {
                var cmd_list: *c.ImDrawList = draw_data.CmdLists[i];

                var vertex_data: []c.ImDrawVert = undefined;
                vertex_data.ptr = cmd_list.VtxBuffer.Data;
                vertex_data.len = @intCast(usize, cmd_list.VtxBuffer.Size);
                var vertex_data_size = @intCast(u32, vertex_data.len * @sizeOf(c.ImDrawVert));
                var vertex_buffer = try Buffer.init(self.device, vertex_data_size, .{ .vertex_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
                try vertex_buffer.fill(c.ImDrawVert, vertex_data);
                try self.freed_buffers.append(vertex_buffer);

                var index_data: []c.ImDrawIdx = undefined;
                index_data.ptr = cmd_list.IdxBuffer.Data;
                index_data.len = @intCast(usize, cmd_list.IdxBuffer.Size);
                var index_data_size = @intCast(u32, index_data.len * @sizeOf(c.ImDrawIdx));
                var index_buffer = try Buffer.init(self.device, index_data_size, .{ .index_buffer_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true });
                try index_buffer.fill(c.ImDrawIdx, index_data);
                try self.freed_buffers.append(index_buffer);

                var offset: u64 = 0;
                self.device.dispatch.cmdBindVertexBuffers(command_buffer, 0, 1, @ptrCast([*]vk.Buffer, &vertex_buffer.handle), @ptrCast([*]const u64, &offset));
                self.device.dispatch.cmdBindIndexBuffer(command_buffer, index_buffer.handle, 0, vk.IndexType.uint16);

                var cmd_i: u32 = 0;
                while (cmd_i < cmd_list.CmdBuffer.Size) : (cmd_i += 1) {
                    var pcmd: c.ImDrawCmd = cmd_list.CmdBuffer.Data[cmd_i];

                    if (pcmd.UserCallback) |callback| {
                        //callback(cmd_list, pcmd);
                    } else {
                        var clip_rect: c.ImVec4 = undefined;
                        clip_rect.x = (pcmd.ClipRect.x - clip_offset.x) * clip_scale.x;
                        clip_rect.y = (pcmd.ClipRect.y - clip_offset.y) * clip_scale.y;
                        clip_rect.z = (pcmd.ClipRect.z - clip_offset.x) * clip_scale.x;
                        clip_rect.w = (pcmd.ClipRect.w - clip_offset.y) * clip_scale.y;

                        if (clip_rect.x < draw_data.DisplaySize.x and clip_rect.y < draw_data.DisplaySize.y and clip_rect.z >= 0.0 and clip_rect.w >= 0.0) {
                            // Negative offsets are illegal for Set Scissor
                            if (clip_rect.x < 0.0) {
                                clip_rect.x = 0.0;
                            }
                            if (clip_rect.y < 0.0) {
                                clip_rect.y = 0.0;
                            }

                            var scissor_rect: vk.Rect2D = undefined;
                            scissor_rect.offset.x = @floatToInt(i32, clip_rect.x);
                            scissor_rect.offset.y = @floatToInt(i32, clip_rect.y);
                            scissor_rect.extent.width = @floatToInt(u32, clip_rect.z - clip_rect.x);
                            scissor_rect.extent.height = @floatToInt(u32, clip_rect.w - clip_rect.y);
                            self.device.dispatch.cmdSetScissor(command_buffer, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor_rect));
                            self.device.dispatch.cmdDrawIndexed(command_buffer, pcmd.ElemCount, 1, pcmd.IdxOffset, 0, 0);
                        }
                    }
                }
            }
        }
    }
};

const ImguiVertex = struct {
    const Self = @This();

    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Self),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @byteOffsetOf(Self, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32_sfloat,
            .offset = @byteOffsetOf(Self, "uv"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r8g8b8a8_unorm,
            .offset = @byteOffsetOf(Self, "color"),
        },
    };

    pos: [2]f32,
    uv: [2]f32,
    color: [4]u8,
};
