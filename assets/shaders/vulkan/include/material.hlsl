const int AlphaModeOpaque = 0;
const int AlphaModeBlend = 1;
const int AlphaModeMask = 2;

struct Material
{
    int alpha_mode;
    float alpha_cutoff;
    int base_color_texture;
    int metallic_roughness_texture;

    int emissive_texture;
    int occlusion_texture;
    int normal_texture;
    int pad0;

    float4 base_color_factor;
    float4 metallic_roughness_factor_pad2;
    float4 emissive_factor_pad;
};
