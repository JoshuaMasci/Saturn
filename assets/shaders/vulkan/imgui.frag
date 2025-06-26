//Bindless Textures
//TODO: use imports instead
[[vk::binding(2, 0)]]
SamplerState BindlessSamplers[] : register(s2, space0);
[[vk::binding(2, 0)]]
Texture2D BindlessTextures[] : register(t2, space0);

float4 sampleTexture(uint index, float2 uv)
{
    return BindlessTextures[index].Sample(BindlessSamplers[index], uv);
}

struct PushConstants
{
    float2 u_scale;
    float2 u_translate;
    uint texture_index;
};

[[vk::push_constant]]
PushConstants push_constants;

struct FragmentInput
{
    [[vk::location(0)]] float4 in_color : COLOR;
    [[vk::location(1)]] float2 in_uv : TEXCOORD0;
};

float4 main(FragmentInput input) : SV_Target
{
    return input.in_color * sampleTexture(push_constants.texture_index, input.in_uv).r;
}
