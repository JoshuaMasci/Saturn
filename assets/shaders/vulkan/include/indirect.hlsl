struct IndirectDrawData {
    //Required by vkCmdDrawIndexedIndirect
    uint32_t    indexCount;
    uint32_t    instanceCount;
    uint32_t    firstIndex;
    int32_t     vertexOffset;
    uint32_t    firstInstance;
};

struct DrawInfo {
    float4x4 model_matrix;
    uint mesh_index;
    uint primitive_index;
    uint material_index;
    uint pad;
};
