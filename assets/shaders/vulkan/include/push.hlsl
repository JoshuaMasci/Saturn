struct PushConstants
{
    float4x4 view_projection_matrix;
    uint32_t mesh_info_binding;
    uint32_t material_binding;

    float4x4 model_matrix;
    uint32_t mesh_index;
    uint32_t primitive_index;
    uint32_t material_index;
};
