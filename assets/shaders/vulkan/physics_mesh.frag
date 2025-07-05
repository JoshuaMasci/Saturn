struct PixelInput
{
    float2 uv0 : TEXCOORD0;
    float4 color: COLOR;
};

struct PixelOutput
{
    float4 out_frag_color : SV_Target;
};

PixelOutput main(PixelInput input)
{
    PixelOutput output;

    output.out_frag_color = input.color;

    return output;
}
