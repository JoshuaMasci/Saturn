#version 450
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference : require

#include "include/push_legacy.glsl"

layout(location = 0) in vec3 frag_postion;
layout(location = 1) in vec3 frag_normal;
layout(location = 2) in vec2 frag_uv0;
layout(location = 3) in vec2 frag_uv1;
layout(location = 4) flat in uint material_index;

layout(location = 0) out vec4 out_frag_color;

//TODO: deduplicate
#define ALPHA_CUTOFF 1
#include "include/pbr_base.glsl"

void main()
{
    FragData data;
    data.position = frag_postion;
    data.normal = frag_normal;
    data.uv0 = frag_uv0;
    data.uv1 = frag_uv1;
    data.material_index = push_constants.material_index;

    out_frag_color = calcColor(push_constants.material_binding, push_constants.texture_binding, data);
}
