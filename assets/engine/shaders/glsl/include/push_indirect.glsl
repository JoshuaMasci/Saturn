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

    uint texture_binding;
    uint material_binding;
} push_constants;
