struct PixelData
{
    float3 color : COLOR;
    float4 position : SV_Position;
};

struct PixelOutput
{
    float4 out_frag_color : SV_Target;
};

PixelOutput main(PixelData input)
{
    PixelOutput output;

    output.out_frag_color = float4(input.color, 1.0);

    return output;
}
