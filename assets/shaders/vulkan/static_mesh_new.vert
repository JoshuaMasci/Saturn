#include "bindless.hlsl"
#include "mesh.hlsl"
#include "push.hlsl"

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

struct PixelInput
{
    float2 frag_uv0 : TEXCOORD0;
    float2 frag_uv1 : TEXCOORD1;
    float4 position : SV_Position;
};

[[vk::push_constant]]
PushConstants push_constants;

ReadOnlyStorageBufferArray(float4x4, model_matrices);
ReadOnlyStorageBufferArray(uint, index_buffers);
ReadOnlyStorageBufferArray(MeshInfo, mesh_infos);
ReadOnlyStorageBufferArray(PrimitiveInfo, primitve_infos);


PixelInput main(uint instanceID : SV_InstanceID, uint vertexID: SV_VertexID)
{
    PixelInput output;

    float4x4 model_matrix = model_matrices[push_constants.model_matrix_buffer_index][instanceID];
    float3x3 normal_matrix = (float3x3)model_matrix;

    MeshInfo mesh_info = mesh_infos[push_constants.static_mesh_binding][push_constants.mesh_index];
    PrimitiveInfo prim_info = primitve_infos[mesh_info.vertex_index_primitive_bindings_pad1.z][push_constants.primitive_index];
    uint current_index = index_buffers[mesh_info.vertex_index_primitive_bindings_pad1.y][vertexID + prim_info.index_offset];
    Vertex input = LoadVertex(storage_buffers[mesh_info.vertex_index_primitive_bindings_pad1.x], current_index + prim_info.vertex_offset);

    float4 world_position = mul(model_matrix, float4(input.position, 1.0f));
    float3 world_normal = normalize(mul(normal_matrix, input.normal));
    float3 world_tangent = normalize(mul(normal_matrix, input.tangent.xyz));

    output.position = mul(push_constants.view_projection_matrix, world_position);
    output.frag_uv0 = input.uv0;
    output.frag_uv1 = input.uv1;

    return output;
}
