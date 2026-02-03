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

//TODO: this
layout(buffer_reference, std430) readonly buffer Meshlets {
    uint data[];
};
layout(buffer_reference, std430) readonly buffer MeshletVertices {
    uint data[];
};
layout(buffer_reference, std430) readonly buffer MeshletTriangles {
    uint data[];
};

struct MeshInfo {
    vec4 sphere_pos_radius;
    uint vertex_offset;
    uint index_offset;
    Primitives primitives;
    Meshlets meshlets;
    MeshletVertices meshlet_vertices;
    MeshletTriangles meshlet_triangles;
    uint meshlet_loaded;
    uint _pad0;
};
