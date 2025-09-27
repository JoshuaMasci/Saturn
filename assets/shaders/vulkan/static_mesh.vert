#include "bindless.hlsl"
#include "mesh.hlsl"
#include "push.hlsl"
#include "indirect.hlsl"

struct PixelInput
{
    float2 frag_uv0 : TEXCOORD0;
    float2 frag_uv1 : TEXCOORD1;
    float4 position : SV_Position;
};

ReadOnlyStorageBufferArray(uint, index_buffers);
ReadOnlyStorageBufferArray(MeshInfo, mesh_infos);
ReadOnlyStorageBufferArray(DrawInfo, draw_infos);

[[vk::push_constant]]
PushConstants push_constants;

PixelInput main(Vertex input, uint instanceID : SV_InstanceID)
{
    PixelInput output;

    DrawInfo info = draw_infos[push_constants.draw_info_binding][instanceID];

    float4x4 model_matrix = info.model_matrix;
    float3x3 normal_matrix = (float3x3)model_matrix;

    float4 world_position = mul(model_matrix, float4(input.position, 1.0f));
    float3 world_normal = normalize(mul(normal_matrix, input.normal));
    float3 world_tangent = normalize(mul(normal_matrix, input.tangent.xyz));

    output.position = mul(push_constants.view_projection_matrix, world_position);
    output.frag_uv0 = input.uv0;
    output.frag_uv1 = input.uv1;

    return output;
}
