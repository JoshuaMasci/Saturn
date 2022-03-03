pub const std = @import("std");
const vk = @import("vulkan");

const BlendOp = enum { add, subtract, reverse_subtract, min, max };
const BlendFactor = enum { zero, one, color_src, one_minus_color_src, color_dst, one_minus_color_dst, alpha_src, one_minus_alpha_src, alpha_dst, one_minus_alpha_dst };
const BlendChannel = struct { op: BlendOp = .add, src_factor: BlendFactor = .one, dst_factor: BlendFactor = .zero };
const BlendState = struct { color: BlendChannel = .{}, alpha: BlendChannel = .{} };

fn get_vk_blend_op(op: BlendOp) vk.BlendOp {
    return switch (op) {
        .add => .add,
        .subtract => .subtract,
        .reverse_subtract => .reverse_subtract,
        .min => .min,
        .max => .max,
    };
}

fn get_vk_blend_factor(factor: BlendFactor) vk.BlendFactor {
    return switch (factor) {
        .zero => .zero,
        .one => .one,
        .color_src => .color_src,
        .one_minus_color_src => .one_minus_color_src,
        .color_dst => .color_dst,
        .one_minus_color_dst => .one_minus_color_dst,
        .alpha_src => .alpha_src,
        .one_minus_alpha_src => .one_minus_alpha_src,
        .alpha_dst => .alpha_dst,
        .one_minus_alpha_dst => .one_minus_alpha_dst,
    };
}

const GraphicsPipelineShaders = struct {
    vertex_module: vk.ShaderModule,
    fragment_module: ?vk.ShaderModule,
};

pub const GraphicsPipelineState = struct {
    const Self = @This();

    cull_mode: enum { none, front, back, all } = .back,

    //TODO: blend ops, this needs to be per attachment one day
    blend_state: ?BlendState = .null,

    //TODO: stencil settings
    depth_test: enum { never, test_only, test_and_write } = .never,
    depth_op: enum { none, less, equal, less_equal, greater, not_equal, greater_equal, always } = .none,

    fn get_cull_flags(self: Self) vk.CullModeFlags {
        return switch (self.cull_mode) {
            .none => .{},
            .front => .{ .front_bit = true },
            .back => .{ .back_bit = true },
            .all => .{ .front_bit = true, .back_bit = true },
        };
    }

    fn get_blend_state(self: Self) vk.PipelineColorBlendAttachmentState {
        return if (self.blend_state) |blend_state| .{
            .blend_enable = vk.FALSE,
            .color_blend_op = get_vk_blend_op(blend_state.color.op),
            .src_color_blend_factor = get_vk_blend_factor(blend_state.color.src_factor),
            .dst_color_blend_factor = get_vk_blend_factor(blend_state.color.dst_factor),
            .alpha_blend_op = get_vk_blend_op(blend_state.alpha.op),
            .src_alpha_blend_factor = get_vk_blend_factor(blend_state.alpha.src_factor),
            .dst_alpha_blend_factor = get_vk_blend_factor(blend_state.alpha.dst_factor),
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        } else .{
            .blend_enable = vk.FALSE,
            .color_blend_op = .add,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .alpha_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };
    }

    fn get_depth_state(self: Self) void {
        _ = self;
        //TODO: Whatever this is
    }
};

const RenderPassInfo = struct {
    color_attachments: std.ArrayList(vk.Format),
    depth_stencil_attachment: ?vk.Format,
};

const VertexInput = struct {};

//TODO: Pipeline Cache
const PipelineCache = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    //pipelines: std.AutoHashMap(),
};

pub fn create_pipeline(
    pipeline_layout: vk.PipelineLayout,
    shaders: *GraphicsPipelineShaders,
    state: *GraphicsPipelineState,
    render_pass: *RenderPassInfo,
    vertex_input: *VertexInput,
) vk.Pipeline {
    //TODO: deal with render pass
    _ = vertex_input;

    var shader_stage_create_info = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .flags = .{},
            .stage = .{ .vertex_bit = true },
            .module = shaders.vertex_module,
            .p_name = "main",
            .p_specialization_info = null,
        },
        .{
            .flags = .{},
            .stage = .{ .fragment_bit = true },
            .module = .null_handle,
            .p_name = "main",
            .p_specialization_info = null,
        },
    };

    if (shaders.fragment_module) |fragment_module| {
        shader_stage_create_info[1].module = fragment_module;
    } else {
        shader_stage_create_info.len = 1;
    }

    //TODO: this
    var input_bingings = [_]vk.VertexInputBindingDescription{};
    var input_attributes = [_]vk.VertexInputAttributeDescription{};

    const vertex_input_state_create_info = vk.PipelineVertexInputStateCreateInfo{
        .flags = .{},
        .vertex_binding_description_count = @intCast(u32, input_bingings.len),
        .p_vertex_binding_descriptions = input_bingings.ptr,
        .vertex_attribute_description_count = @intCast(u32, input_attributes.len),
        .p_vertex_attribute_descriptions = input_attributes.ptr,
    };

    const input_assembly_state_create_info = vk.PipelineInputAssemblyStateCreateInfo{
        .flags = .{},
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const viewport_state_create_info = vk.PipelineViewportStateCreateInfo{
        .flags = .{},
        .viewport_count = 1,
        .p_viewports = undefined,
        .scissor_count = 1,
        .p_scissors = undefined,
    };

    const rasterization_state_create_info = vk.PipelineRasterizationStateCreateInfo{
        .flags = .{},
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = state.get_cull_flags(),
        .front_face = .counter_clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const multisample_state_create_info = vk.PipelineMultisampleStateCreateInfo{
        .flags = .{},
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const color_blend_attachment_states = [_]vk.PipelineColorBlendAttachmentState{state.get_blend_state()};
    const color_blend_state_create_info = vk.PipelineColorBlendStateCreateInfo{
        .flags = .{},
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = color_blend_attachment_states.len,
        .p_attachments = color_blend_attachment_states.ptr,
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynamic_state = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state_create_info = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynamic_state.len,
        .p_dynamic_states = dynamic_state.ptr,
    };

    //TODO: depth testing
    const graphics_pipeline_create_infos = [_]vk.GraphicsPipelineCreateInfo{.{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &shader_stage_create_info,
        .p_vertex_input_state = &vertex_input_state_create_info,
        .p_input_assembly_state = &input_assembly_state_create_info,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_state_create_info,
        .p_rasterization_state = &rasterization_state_create_info,
        .p_multisample_state = &multisample_state_create_info,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &color_blend_state_create_info,
        .p_dynamic_state = &dynamic_state_create_info,
        .layout = pipeline_layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    }};

    var pipeline: vk.Pipeline = .null_handle;

    _ = graphics_pipeline_create_infos;
    // _ = try self.dispatch.createGraphicsPipelines(
    //     self.handle,
    //     .null_handle,
    //     graphics_pipeline_create_infos.len,
    //     graphics_pipeline_create_infos.ptr,
    //     null,
    //     @ptrCast([*]vk.Pipeline, &pipeline),
    // );

    return pipeline;
}
