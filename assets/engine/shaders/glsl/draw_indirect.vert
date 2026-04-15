#version 450
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference : require

#include "include/push_indirect.glsl"

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
    const DrawIndexedIndirectCommandInfo cmd = push_constants.indirect_command_infos_ptr.cmds[gl_InstanceIndex];
    const Instance instance = push_constants.scene_instances_ptr.instances[cmd.instance_index];

    const mat4 model_matrix = instance.model_matrix;
    const mat3 normal_matrix = mat3(instance.normal_matrix);

    vec4 world_position = model_matrix * vec4(position, 1.0f);
    vec3 world_normal = normalize(normal_matrix * normal);
    vec3 world_tangent = normalize(normal_matrix * tangent.xyz);

    frag_postion = world_position.xyz;
    frag_normal = world_normal;

    frag_uv0 = uv0,
    frag_uv1 = uv1,
    material_index = cmd.material_index;

    gl_Position = push_constants.view_projection_matrix * world_position;
}
