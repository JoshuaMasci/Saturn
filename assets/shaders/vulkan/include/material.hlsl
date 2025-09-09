const int AlphaModeOpaque = 0;
const int AlphaModeBlend = 1;
const int AlphaModeMask = 2;

struct Material
{
    int alpha_mode;
    float alpha_cutoff;
    uint base_color_texture;
    uint metallic_roughness_texture;

    uint emissive_texture;
    uint occlusion_texture;
    uint normal_texture;
    int pad0;

    float4 base_color_factor;
    float4 metallic_roughness_factor_pad2;
    float4 emissive_factor_pad;
};
