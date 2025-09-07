enum AlphaMode {
    Opaque = 0,
    Blend = 1,
    Mask = 2,
};

struct Material
{
    AlphaMode alpha_mode;
    float alpha_cutoff;

    int base_color_texture_index;
    int metallic_roughness_texture_index;
    int emissive_texture_index;
    int occlusion_texture_index;
    int normal_texture_index;

    float4 base_color_factor;
    float2 metallic_roughness_factor;
    float3 emissive_factor;
};
