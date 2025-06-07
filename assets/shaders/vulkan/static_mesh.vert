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
    float4x4 model_matrix;
    float4 base_color_factor;
};

[[vk::push_constant]]
PushConstants push_constants;

PixelInput main(VertexInput input)
{
    PixelInput output;

    float3x3 normal_matrix = (float3x3)push_constants.model_matrix;

    float4 world_position = mul(push_constants.model_matrix, float4(input.position, 1.0f));
    float3 world_normal = normalize(mul(normal_matrix, input.normal));
    float3 world_tangent = normalize(mul(normal_matrix, input.tangent.xyz));

    output.position = mul(push_constants.view_projection_matrix, world_position);

    output.frag_uv0 = input.uv0;

    return output;
}
