#version 450
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference : require

#include "include/scene.glsl"
#include "include/indirect.glsl"

layout(std430, buffer_reference, buffer_reference_align = 8) readonly buffer SceneInstanceBuffer
{
    Instance instances[];
};

layout(std430, buffer_reference, buffer_reference_align = 8) readonly buffer IndirectCommandInfosBuffer
{
    DrawIndexedIndirectCommandInfo cmds[];
};

layout(push_constant) uniform PushConstants
{
    mat4 view_projection_matrix;

    SceneInstanceBuffer scene_instances_ptr;
    IndirectCommandInfosBuffer indirect_command_infos_ptr;

    uint material_binding;
} push_constants;

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec4 tangent;
layout(location = 3) in vec2 uv0;
layout(location = 4) in vec2 uv1;

layout(location = 0) out vec2 frag_uv0;
layout(location = 1) out vec2 frag_uv1;
layout(location = 2) flat out uint material_index;

void main()
{
    const DrawIndexedIndirectCommandInfo cmd = push_constants.indirect_command_infos_ptr.cmds[gl_InstanceIndex];
    const Instance instance = push_constants.scene_instances_ptr.instances[cmd.instance_index];

    const mat4 model_matrix = instance.model_matrix;
    mat3 normal_matrix = mat3(instance.normal_matrix);

    vec4 world_position = model_matrix * vec4(position, 1.0f);
    vec3 world_normal = normalize(normal_matrix * normal);
    vec3 world_tangent = normalize(normal_matrix * tangent.xyz);

    gl_Position = push_constants.view_projection_matrix * world_position;
    frag_uv0 = uv0,
    frag_uv1 = uv1,
    material_index = cmd.material_index;
}
