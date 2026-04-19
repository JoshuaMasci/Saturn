struct Instance
{
    mat4 model_matrix;
    mat4 normal_matrix;
    uint mesh_index;
    uint visible;
    uint pad0;
    uint pad1;
};

struct PrimitiveInstance
{
    uint visible;
    uint instance_index;
    uint primitive_index;
    uint material_instance_index;
};
