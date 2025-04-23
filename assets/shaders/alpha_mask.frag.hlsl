// Input structure
struct PixelInput
{
    float2 frag_uv0 : TEXCOORD0;
};

// Output structure
struct PixelOutput
{
    float4 out_frag_color : SV_Target;
};

// Uniforms
cbuffer MaterialBuffer : register(b0, space3)
{
    float4 base_color_factor;
    int base_color_texture_enable;  // Default to 0
    float alpha_cutoff;
};

// Texture and sampler
Texture2D base_color_texture : register(t0, space2);
SamplerState base_color_sampler : register(s0, space2);

// Main fragment shader function
PixelOutput main(PixelInput input)
{
    PixelOutput output;

    // Start with base color from factor
    float4 base_color = base_color_factor;

    // Apply texture if enabled
    if (base_color_texture_enable != 0)
    {
        base_color *= base_color_texture.Sample(base_color_sampler, input.frag_uv0);
    }

    if (base_color.w < alpha_cutoff)
    {
        discard;
    }


    // Set the final color for the fragment
    output.out_frag_color = base_color;

    return output;
}
