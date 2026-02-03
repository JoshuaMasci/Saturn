#version 450
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference : require

layout(push_constant) uniform PushConstants
{
    mat4 view_projection_matrix;
    mat4 model_matrix;
    uint material_binding;
    uint material_index;
} push_constants;

#define ALPHA_CUTOFF 1

#include "pbr_base.glsl"
