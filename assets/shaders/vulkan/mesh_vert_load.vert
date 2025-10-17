#include "bindless.hlsl"
#include "mesh.hlsl"
#include "vertex_data.hlsl"
#include "push.hlsl"

[[vk::push_constant]]
PushConstants push_constants;

ReadOnlyStorageBufferArray(MeshInfo, mesh_infos);

VertexData main(uint instanceID : SV_InstanceID, uint vertexID: SV_VertexID)
{
    VertexData output;

    output.material_index = push_constants.material_index;

    float4x4 model_matrix = push_constants.model_matrix;
    float3x3 normal_matrix = (float3x3)model_matrix;

    MeshInfo mesh_info = mesh_infos[push_constants.mesh_info_binding][push_constants.mesh_index];
    ByteAddressBuffer geo_buffer = storage_buffers[mesh_info.buffer_binding];
    PrimitiveInfo prim_info = LoadPrimitiveInfo(geo_buffer, mesh_info.primitives_offset, push_constants.primitive_index);

    uint current_index = LoadIndex(geo_buffer, mesh_info.indices_offset, vertexID + prim_info.index_offset);
    Vertex input = LoadVertex(geo_buffer, mesh_info.vertices_offset, current_index + prim_info.vertex_offset);

    float4 world_position = mul(model_matrix, float4(input.position, 1.0f));
    float3 world_normal = normalize(mul(normal_matrix, input.normal));
    float3 world_tangent = normalize(mul(normal_matrix, input.tangent.xyz));

    output.position = mul(push_constants.view_projection_matrix, world_position);
    output.frag_uv0 = input.uv0;
    output.frag_uv1 = input.uv1;

    return output;
}
