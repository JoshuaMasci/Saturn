struct Vertex
{
    float3 position : POSITION;
    float3 normal   : NORMAL;
    float4 tangent  : TANGENT;
    float2 uv0      : TEXCOORD0;
    float2 uv1      : TEXCOORD1;
};

// Vertex: 56 bytes size
// position: 0 bytes offset
// normal: 12 bytes offset
// tangent: 24 bytes offset
// uv0: 40 bytes offset
// uv1: 48 bytes offset

Vertex LoadVertex(ByteAddressBuffer buffer, uint vertexID)
{
    const uint VERTEX_SIZE = 56;
    uint offset = vertexID * VERTEX_SIZE;

    Vertex v;
    v.position = asfloat(buffer.Load3(offset + 0));
    v.normal   = asfloat(buffer.Load3(offset + 12));
    v.tangent  = asfloat(buffer.Load4(offset + 24));
    v.uv0      = asfloat(buffer.Load2(offset + 40));
    v.uv1      = asfloat(buffer.Load2(offset + 48));
    return v;
}

struct MeshInfo {
    float4 sphere_pos_radius;
    uint4 vertex_index_primitive_bindings_pad1;
    uint4 meshlet_vertex_triangle_bindings_pad1;
};

struct PrimitiveInfo {
    float4 sphere_pos_radius;
    uint vertex_offset;
    uint vertex_count;
    uint index_offset;
    uint index_count;
    uint meshlet_offset;
    uint meshlet_count;
    uint pad0;
    uint pad1;
};
