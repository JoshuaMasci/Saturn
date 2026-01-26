struct Instance
{
    mat4 model_matrix;
    mat4 normal_matrix;
    uint visable;
};

struct PrimitiveInstance
{
    uint instance_index;
    uint mesh_index;
    uint primitive_index;
    uint material_instance_index;
};
