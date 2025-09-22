struct PushConstants
{
    float4x4 view_projection_matrix;
    uint model_matrix_buffer_index;
    uint static_mesh_binding;
    uint material_binding;
    uint mesh_index;
    uint primitive_index;
    uint material_index;
};
