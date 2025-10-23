#define MAX_PRIMITIVE_COUNT 8

struct Instance
{
    float4x4 model_matrix;
    uint32_t mesh_index;
    uint32_t primitive_offset;
    uint32_t primitive_count;
    uint32_t visable;
    uint32_t material_indexes[MAX_PRIMITIVE_COUNT];
};
