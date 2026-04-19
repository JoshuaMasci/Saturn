struct Material
{
    uint loaded;
    int alpha_mode;
    float alpha_cutoff;
    uint base_color_texture;
    uint metallic_roughness_texture;

    uint emissive_texture;
    uint occlusion_texture;
    uint normal_texture;

    vec4 base_color_factor;
    vec4 metallic_roughness_factor_pad2;
    vec4 emissive_factor_pad;
};
