#include "bindless.hlsl"

struct VertexInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv0 : TEXCOORD0;
};

struct PixelInput
{
    float2 frag_uv0 : TEXCOORD0;
    float4 position : SV_Position;
};

struct PushConstants
{
    float4x4 view_projection_matrix;
    uint model_matrix_buffer_index;
    uint material_binding;
    uint material_index;
};

[[vk::push_constant]]
PushConstants push_constants;

ReadOnlyStorageBufferArray(float4x4, model_matrices);

PixelInput main(VertexInput input, uint instanceID : SV_InstanceID)
{
    PixelInput output;

    float4x4 model_matrix = model_matrices[push_constants.model_matrix_buffer_index][instanceID];

    float3x3 normal_matrix = (float3x3)model_matrix;

    float4 world_position = mul(model_matrix, float4(input.position, 1.0f));
    float3 world_normal = normalize(mul(normal_matrix, input.normal));
    float3 world_tangent = normalize(mul(normal_matrix, input.tangent.xyz));

    output.position = mul(push_constants.view_projection_matrix, world_position);

    output.frag_uv0 = input.uv0;

    return output;
}
