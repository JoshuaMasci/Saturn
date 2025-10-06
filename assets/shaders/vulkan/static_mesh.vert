#include "bindless.hlsl"
#include "mesh.hlsl"
#include "push.hlsl"
#include "indirect.hlsl"

struct VertexData
{
    float2 frag_uv0 : TEXCOORD0;
    float2 frag_uv1 : TEXCOORD1;
    uint material_index: MAT;
    float4 position : SV_Position;
};

ReadOnlyStorageBufferArray(uint, index_buffers);
ReadOnlyStorageBufferArray(MeshInfo, mesh_infos);
ReadOnlyStorageBufferArray(PrimitiveInfo, primitve_infos);
ReadOnlyStorageBufferArray(DrawInfo, draw_infos);

[[vk::push_constant]]
PushConstants push_constants;

VertexData main(uint instanceID : SV_InstanceID, uint vertexID: SV_VertexID)
{
    VertexData output;

    DrawInfo info = draw_infos[push_constants.draw_info_binding][instanceID];
    output.material_index = info.material_index;

    float4x4 model_matrix = info.model_matrix;
    float3x3 normal_matrix = (float3x3)model_matrix;

    MeshInfo mesh_info = mesh_infos[push_constants.static_mesh_binding][info.mesh_index];
    PrimitiveInfo prim_info = primitve_infos[mesh_info.vertex_index_primitive_bindings_pad1.z][info.primitive_index];
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
