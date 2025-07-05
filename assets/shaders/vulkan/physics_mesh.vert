struct VertexInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv0 : TEXCOORD0;
    float4 color: COLOR;
};

struct PixelInput
{
    float2 uv0 : TEXCOORD0;
    float4 color: COLOR;
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

    float4 world_position = mul(push_constants.model_matrix, float4(input.position, 1.0f));
    output.position = mul(push_constants.view_projection_matrix, world_position);

    output.uv0 = input.uv0;
    output.color = input.color * push_constants.base_color_factor;

    return output;
}
