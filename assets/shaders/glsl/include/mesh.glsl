struct Vertex
{
    vec3 position;
    vec3 normal;
    vec4 tangent;
    vec2 uv0;
    vec2 uv1;
};

struct PrimitiveInfo {
    vec4 sphere_pos_radius;
    uint vertex_offset;
    uint vertex_count;
    uint index_offset;
    uint index_count;
    uint meshlet_offset;
    uint meshlet_count;
    uint pad0;
    uint pad1;
};

layout(std430, buffer_reference) readonly buffer Vertices {
    Vertex v[];
};

layout(std430, buffer_reference) readonly buffer Indices {
    uint i[];
};

layout(std430, buffer_reference) readonly buffer Primitives {
    PrimitiveInfo p[];
};

struct MeshInfo {
    vec4 sphere_pos_radius;
    Vertices vertices;
    Indices indices;
    Primitives primitives;
};
