#include "bindless.hlsl"
#include "mesh.hlsl"
#include "vertex_data.hlsl"
#include "push.hlsl"

[[vk::push_constant]]
PushConstants push_constants;

VertexData main(Vertex input, uint instanceID : SV_InstanceID, uint vertexID: SV_VertexID)
{
    VertexData output;

    output.material_index = push_constants.material_index;

    float4x4 model_matrix = push_constants.model_matrix;
    float3x3 normal_matrix = (float3x3)model_matrix;

    float4 world_position = mul(model_matrix, float4(input.position, 1.0f));
    float3 world_normal = normalize(mul(normal_matrix, input.normal));
    float3 world_tangent = normalize(mul(normal_matrix, input.tangent.xyz));

    output.position = mul(push_constants.view_projection_matrix, world_position);
    output.frag_uv0 = input.uv0;
    output.frag_uv1 = input.uv1;

    return output;
}
