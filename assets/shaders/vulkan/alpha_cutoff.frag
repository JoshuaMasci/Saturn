#include "bindless.hlsl"

struct PixelInput
{
    float2 frag_uv0 : TEXCOORD0;
};

struct PixelOutput
{
    float4 out_frag_color : SV_Target;
};

struct PushConstants
{
    float4x4 view_projection_matrix;
    float4x4 model_matrix;
    float4 base_color_factor;
    uint base_color_texture;
    float alpha_cutoff;
};

[[vk::push_constant]]
PushConstants push_constants;

PixelOutput main(PixelInput input)
{
    PixelOutput output;

    float4 base_color = push_constants.base_color_factor;

	if (push_constants.base_color_texture != 0) {
		base_color *= sampleTexture(push_constants.base_color_texture, input.frag_uv0);
	}

    if (base_color.w < push_constants.alpha_cutoff) {
        discard;
    }

    output.out_frag_color = base_color;

    return output;
}
