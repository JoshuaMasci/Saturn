#version 450
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : enable

#include "include/push_legacy.glsl"

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec4 tangent;
layout(location = 3) in vec2 uv0;
layout(location = 4) in vec2 uv1;

layout(location = 0) out vec3 frag_postion;
layout(location = 1) out vec3 frag_normal;
layout(location = 2) out vec2 frag_uv0;
layout(location = 3) out vec2 frag_uv1;
layout(location = 4) flat out uint material_index;

void main()
{
    const mat4 model_matrix = push_constants.model_matrix;
    mat3 normal_matrix = mat3(model_matrix);

    vec4 world_position = model_matrix * vec4(position, 1.0f);
    vec3 world_normal = normalize(normal_matrix * normal);
    vec3 world_tangent = normalize(normal_matrix * tangent.xyz);

    frag_postion = world_position.xyz;
    frag_normal = world_normal;

    frag_uv0 = uv0,
    frag_uv1 = uv1,
    material_index = push_constants.material_index;

    gl_Position = push_constants.view_projection_matrix * world_position;
}
