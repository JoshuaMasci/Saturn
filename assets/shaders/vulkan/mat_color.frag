struct VertexData
{
    float2 frag_uv0 : TEXCOORD0;
    float2 frag_uv1 : TEXCOORD1;
    uint material_index: MAT;
    float4 position : SV_Position;
};

float3 HSVtoRGB(float h, float s, float v) {
    float3 rgb = float3(0.0, 0.0, 0.0);

    float c = v * s;
    float x = c * (1.0 - abs(fmod(h * 6.0, 2.0) - 1.0));
    float m = v - c;

    if (h < 1.0/6.0)
        rgb = float3(c, x, 0.0);
    else if (h < 2.0/6.0)
        rgb = float3(x, c, 0.0);
    else if (h < 3.0/6.0)
        rgb = float3(0.0, c, x);
    else if (h < 4.0/6.0)
        rgb = float3(0.0, x, c);
    else if (h < 5.0/6.0)
        rgb = float3(x, 0.0, c);
    else
        rgb = float3(c, 0.0, x);

    return rgb + m;
}

float3 UIntToDistinctColor(uint id) {
    // Use golden ratio to distribute hues evenly
    float golden_ratio_conjugate = 0.61803398875;
    float hue = frac(id * golden_ratio_conjugate);  // Range [0,1)

    float saturation = 0.6;  // You can adjust for vividness
    float value = 0.95;      // Brightness

    return HSVtoRGB(hue, saturation, value);
}

float4 main(VertexData input) : SV_TARGET
{
    //const float3 color = float3(1.0, 1.0, 1.0);
    const float3 color = UIntToDistinctColor(input.material_index);
    return float4(color, 1);
}
