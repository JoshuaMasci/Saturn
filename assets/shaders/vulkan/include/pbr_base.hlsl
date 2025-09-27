//Base Pbr Frag Shader, final shader will use defines to affect behavior

#include "bindless.hlsl"
#include "material.hlsl"
#include "push.hlsl"

ReadOnlyStorageBufferArray(Material, materialBuffer);

struct PixelInput
{
    float2 frag_uv0 : TEXCOORD0;
    float2 frag_uv1 : TEXCOORD1;
    uint material_index: MAT;
};

struct PixelOutput
{
    float4 out_frag_color : SV_Target;
};

[[vk::push_constant]]
PushConstants push_constants;

PixelOutput main(PixelInput input)
{
    PixelOutput output;

    Material material = materialBuffer[push_constants.material_binding][input.material_index];

    float4 base_color = material.base_color_factor;

	if (material.base_color_texture != 0) {
		base_color *= sampleTexture(material.base_color_texture, input.frag_uv0);
	}

	#ifdef ALPHA_CUTOFF
    if (base_color.w < material.alpha_cutoff) {
        discard;
    }
    #endif

    output.out_frag_color = base_color;

    return output;
}
