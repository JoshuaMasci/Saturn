struct PushConstants
{
    float4x4 view_projection_matrix;
    uint mesh_info_binding;
    uint material_binding;

    float4x4 model_matrix;
    uint mesh_index;
    uint primitive_index;
    uint material_index;
};
