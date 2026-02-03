struct Instance
{
    mat4 model_matrix;
    mat4 normal_matrix;
    uint mesh_index;
    uint visable;
    uint pad0;
    uint pad1;
};

struct PrimitiveInstance
{
    uint instance_index;
    uint primitive_index;
    uint material_instance_index;
    uint pad0;
};
