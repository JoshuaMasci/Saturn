const std = @import("std");
const vk = @import("vulkan");

const MeshAsset = @import("../../asset/mesh.zig");

pub const PipelineConfig = struct {
    color_format: vk.Format,
    depth_format: ?vk.Format = null,
    sample_count: vk.SampleCountFlags = .{ .@"1_bit" = true },
    cull_mode: vk.CullModeFlags = .{ .back_bit = true },
    front_face: vk.FrontFace = .counter_clockwise,
    polygon_mode: vk.PolygonMode = .fill,
    enable_depth_test: bool = true,
    enable_depth_write: bool = true,
    depth_compare_op: vk.CompareOp = .less,
    enable_blending: bool = false,
};

pub const PipelineError = error{
    ShaderModuleCreationFailed,
    PipelineCreationFailed,
    OutOfMemory,
};

pub fn createGraphicsPipeline(
    allocator: std.mem.Allocator,
    device: vk.DeviceProxy,
    pipeline_layout: vk.PipelineLayout,
    config: PipelineConfig,
    vertex_module: vk.ShaderModule,
    fragment_module: ?vk.ShaderModule,
) PipelineError!vk.Pipeline {
    _ = allocator; // Currently unused, but available for future extensions

    // Shader stage create infos
    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .flags = .{},
            .stage = .{ .vertex_bit = true },
            .module = vertex_module,
            .p_name = "main",
            .p_specialization_info = null,
        },
        .{
            .flags = .{},
            .stage = .{ .fragment_bit = true },
            .module = fragment_module orelse .null_handle,
            .p_name = "main",
            .p_specialization_info = null,
        },
    };

    const vertex_binding_descriptions = [_]vk.VertexInputBindingDescription{
        .{
            .binding = 0,
            .stride = @sizeOf(MeshAsset.Vertex),
            .input_rate = .vertex,
        },
    };

    const vertex_attribute_descriptions = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32b32_sfloat, // FLOAT3
            .offset = @offsetOf(MeshAsset.Vertex, "position"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat, // FLOAT3
            .offset = @offsetOf(MeshAsset.Vertex, "normal"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32b32a32_sfloat, // FLOAT4
            .offset = @offsetOf(MeshAsset.Vertex, "tangent"),
        },
        .{
            .binding = 0,
            .location = 3,
            .format = .r32g32_sfloat, // FLOAT2
            .offset = @offsetOf(MeshAsset.Vertex, "uv0"),
        },
        .{
            .binding = 0,
            .location = 4,
            .format = .r32g32_sfloat, // FLOAT2
            .offset = @offsetOf(MeshAsset.Vertex, "uv1"),
        },
    };

    const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = vertex_binding_descriptions.len,
        .p_vertex_binding_descriptions = &vertex_binding_descriptions,
        .vertex_attribute_description_count = vertex_attribute_descriptions.len,
        .p_vertex_attribute_descriptions = &vertex_attribute_descriptions,
    };

    // Input assembly state
    const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
        .flags = .{},
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    // Viewport state (using dynamic state)
    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .flags = .{},
        .viewport_count = 1,
        .p_viewports = null, // Dynamic
        .scissor_count = 1,
        .p_scissors = null, // Dynamic
    };

    // Rasterization state
    const rasterizer = vk.PipelineRasterizationStateCreateInfo{
        .flags = .{},
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = config.polygon_mode,
        .line_width = 1.0,
        .cull_mode = config.cull_mode,
        .front_face = config.front_face,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0.0,
        .depth_bias_clamp = 0.0,
        .depth_bias_slope_factor = 0.0,
    };

    // Multisampling state
    const multisampling = vk.PipelineMultisampleStateCreateInfo{
        .flags = .{},
        .sample_shading_enable = vk.FALSE,
        .rasterization_samples = config.sample_count,
        .min_sample_shading = 1.0,
        .p_sample_mask = null,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    // Depth stencil state
    const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
        .flags = .{},
        .depth_test_enable = if (config.enable_depth_test and config.depth_format != null) vk.TRUE else vk.FALSE,
        .depth_write_enable = if (config.enable_depth_write and config.depth_format != null) vk.TRUE else vk.FALSE,
        .depth_compare_op = config.depth_compare_op,
        .depth_bounds_test_enable = vk.FALSE,
        .min_depth_bounds = 0.0,
        .max_depth_bounds = 1.0,
        .stencil_test_enable = vk.FALSE,
        .front = std.mem.zeroes(vk.StencilOpState),
        .back = std.mem.zeroes(vk.StencilOpState),
    };

    // Color blend attachment state
    const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        .blend_enable = if (config.enable_blending) vk.TRUE else vk.FALSE,
        .src_color_blend_factor = .src_alpha,
        .dst_color_blend_factor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
    };

    // Color blend state
    const color_blending = vk.PipelineColorBlendStateCreateInfo{
        .flags = .{},
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_blend_attachment),
        .blend_constants = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    // Dynamic states
    const dynamic_states = [_]vk.DynamicState{
        .viewport,
        .scissor,
    };

    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
    };

    // Rendering info for dynamic rendering (Vulkan 1.3 / VK_KHR_dynamic_rendering)
    const color_attachment_format = [_]vk.Format{config.color_format};
    const pipeline_rendering_create_info = vk.PipelineRenderingCreateInfo{
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachment_formats = &color_attachment_format,
        .depth_attachment_format = config.depth_format orelse .undefined,
        .stencil_attachment_format = .undefined,
    };

    // Graphics pipeline create info
    const pipeline_info = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = if (fragment_module != null) 2 else 1,
        .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input_info,
        .p_input_assembly_state = &input_assembly,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterizer,
        .p_multisample_state = &multisampling,
        .p_depth_stencil_state = &depth_stencil,
        .p_color_blend_state = &color_blending,
        .p_dynamic_state = &dynamic_state,
        .layout = pipeline_layout,
        .render_pass = .null_handle, // Using dynamic rendering
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
        .p_next = &pipeline_rendering_create_info,
    };

    var pipeline: vk.Pipeline = undefined;
    const result = device.createGraphicsPipelines(
        .null_handle, // pipeline cache
        1,
        @ptrCast(&pipeline_info),
        null, // allocator
        @ptrCast(&pipeline),
    ) catch return PipelineError.PipelineCreationFailed;

    if (result != .success) {
        return PipelineError.PipelineCreationFailed;
    }

    return pipeline;
}
