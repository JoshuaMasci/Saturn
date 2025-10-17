struct Vertex
{
    float3 position : POSITION;
    float3 normal   : NORMAL;
    float4 tangent  : TANGENT;
    float2 uv0      : TEXCOORD0;
    float2 uv1      : TEXCOORD1;
};

struct MeshInfo {
    float4 sphere_pos_radius;
    uint buffer_binding;
    uint vertices_offset;
    uint indices_offset;
    uint primitives_offset;

    uint meshlets_loaded; //May not use this, but I needed a u32 of padding anyways
    uint meshlets_offset;
    uint meshlet_vertices_offset;
    uint meshlet_triangles_offset;
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

Vertex LoadVertex(ByteAddressBuffer buffer, uint buffer_offset, uint index)
{
    // Vertex: 56 bytes size
    // position: 0 bytes offset
    // normal: 12 bytes offset
    // tangent: 24 bytes offset
    // uv0: 40 bytes offset
    // uv1: 48 bytes offset

    const uint VERTEX_SIZE = 56;
    const uint offset = buffer_offset + (index * VERTEX_SIZE);

    Vertex v;
    v.position = asfloat(buffer.Load3(offset + 0));
    v.normal   = asfloat(buffer.Load3(offset + 12));
    v.tangent  = asfloat(buffer.Load4(offset + 24));
    v.uv0      = asfloat(buffer.Load2(offset + 40));
    v.uv1      = asfloat(buffer.Load2(offset + 48));
    return v;
}

PrimitiveInfo LoadPrimitiveInfo(ByteAddressBuffer buffer, uint buffer_offset, uint index)
{
    const uint PRIMITIVE_SIZE = 48;
    const uint offset = buffer_offset + (index * PRIMITIVE_SIZE);

    PrimitiveInfo info;
    info.sphere_pos_radius = asfloat(buffer.Load4(offset));
    uint4 rest = buffer.Load4(offset + 16);
    info.vertex_offset     = rest.x;
    info.vertex_count      = rest.y;
    info.index_offset      = rest.z;
    info.index_count       = rest.w;

    rest = buffer.Load4(offset + 32);
    info.meshlet_offset    = rest.x;
    info.meshlet_count     = rest.y;
    info.pad0              = rest.z;
    info.pad1              = rest.w;

    return info;
}

uint LoadIndex(ByteAddressBuffer buffer, uint buffer_offset, uint index)
{
    const uint INDEX_SIZE = 4;
    const uint offset = buffer_offset + (index * INDEX_SIZE);
    return buffer.Load(offset);
}
