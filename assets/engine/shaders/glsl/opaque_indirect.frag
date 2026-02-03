#version 450
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_buffer_reference : require

// Dummy Definitions
layout(std430, buffer_reference, buffer_reference_align = 8) readonly buffer SceneInstanceBuffer
{
    uint instances[];
};
layout(std430, buffer_reference, buffer_reference_align = 8) readonly buffer IndirectCommandInfosBuffer
{
    uint cmds[];
};

layout(push_constant) uniform PushConstants
{
    mat4 view_projection_matrix;

    SceneInstanceBuffer scene_instances_ptr;
    IndirectCommandInfosBuffer indirect_command_infos_ptr;

    uint material_binding;
} push_constants;

#include "pbr_base.glsl"
