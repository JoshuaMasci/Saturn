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

// Push constants structure
struct PushConstants
{
    float4x4 view_projection_matrix;
    float4x4 model_matrix;
    float4 base_color_factor;
    uint base_color_texture;
};

// Push constants declaration
[[vk::push_constant]]
PushConstants push_constants;

// Main fragment shader function
PixelOutput main(PixelInput input)
{
    PixelOutput output;

    // Start with base color from factor
    float4 base_color = push_constants.base_color_factor;

	if (push_constants.base_color_texture != 0) {
		base_color *= sampleTexture(push_constants.base_color_texture, input.frag_uv0);
	}

    // Set the final color for the fragment
    output.out_frag_color = base_color;

    return output;
}
