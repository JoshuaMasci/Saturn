struct VkDrawIndexedIndirectCommand {
    uint indexCount;
    uint instanceCount;
    uint firstIndex;
    int vertexOffset;
    uint firstInstance;
};

struct VkDrawIndirectCommand {
    uint vertexCount;
    uint instanceCount;
    uint firstVertex;
    uint firstInstance;
};

struct DrawIndexedIndirectCommandInfo {
    VkDrawIndexedIndirectCommand cmd;

    uint instance_index;
    uint material_index;
};
