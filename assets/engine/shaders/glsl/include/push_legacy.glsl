layout(push_constant) uniform PushConstants
{
    mat4 view_projection_matrix;
    mat4 model_matrix;
    uint texture_binding;
    uint material_binding;
    uint material_index;
} push_constants;
