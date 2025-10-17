#define MAX_VERTICES_PER_MESHLET 64
#define MAX_TRIANGLES_PER_MESHLET 128

struct MeshletInfo {
    float4 sphere_pos_radius;
    uint vertex_offset;
    uint vertex_count;
    uint triangle_offset;
    uint triangle_count;
};

MeshletInfo LoadMeshletInfo(ByteAddressBuffer buffer, uint buffer_offset, uint index)
{
    const uint MESHLET_SIZE = 32;
    const uint offset = buffer_offset + (index * MESHLET_SIZE);

    MeshletInfo info;
    info.sphere_pos_radius = asfloat(buffer.Load4(offset));

    uint4 rest = buffer.Load4(offset + 16);
    info.vertex_offset     = rest.x;
    info.vertex_count      = rest.y;
    info.triangle_offset   = rest.z;
    info.triangle_count    = rest.w;

    return info;
}

uint LoadByte(ByteAddressBuffer buffer, uint buffer_offset, uint index)
{
    uint offset = buffer_offset + index;

    // Load returns a 32-bit value, so we need to extract the correct byte from it.
    uint byte_offset = offset & ~3;            // Align to 4-byte boundary
    uint byte_shift  = (offset & 3) * 8;       // Shift to correct byte position
    uint word       = buffer.Load(byte_offset);
    return (word >> byte_shift) & 0xFF;
}
