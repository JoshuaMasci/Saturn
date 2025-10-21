struct PushConstants
{
    float2 u_scale;
    float2 u_translate;
    uint32_t texture_index;
};

[[vk::push_constant]]
PushConstants push_constants;

struct VertexInput
{
    [[vk::location(0)]] float2 a_pos : POSITION;
    [[vk::location(1)]] float2 a_uv : TEXCOORD0;
    [[vk::location(2)]] float4 a_color : COLOR;
};

struct VertexOutput
{
    float4 gl_position : SV_Position;
    [[vk::location(0)]] float4 out_color : COLOR;
    [[vk::location(1)]] float2 out_uv : TEXCOORD0;
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;
    output.out_color = input.a_color;
    output.out_uv = input.a_uv;
    output.gl_position = float4(input.a_pos * push_constants.u_scale + push_constants.u_translate, 0.0f, 1.0f);
    return output;
}
