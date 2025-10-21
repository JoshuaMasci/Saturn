struct VkDrawIndexedIndirectCommand {
    uint32_t    indexCount;
    uint32_t    instanceCount;
    uint32_t    firstIndex;
    int32_t     vertexOffset;
    uint32_t    firstInstance;
};

struct VkDrawIndirectCommand {
    uint32_t    vertexCount;
    uint32_t    instanceCount;
    uint32_t    firstVertex;
    uint32_t    firstInstance;
};

struct IndirectDrawInfo {
    float4x4 model_matrix;
    uint32_t mesh_index;
    uint32_t primitive_index;
    uint32_t material_index;
    uint32_t pad;
};
