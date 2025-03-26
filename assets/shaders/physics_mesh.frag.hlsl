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
};


// Main fragment shader function
PixelOutput main(PixelInput input)
{
    PixelOutput output;

    // Start with base color from factor
    float4 base_color = base_color_factor;

    // Set the final color for the fragment
    output.out_frag_color = base_color;

    return output;
}
