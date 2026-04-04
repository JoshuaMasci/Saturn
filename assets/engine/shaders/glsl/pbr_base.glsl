#include "include/bindless.glsl"
#include "include/texture.glsl"

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

    vec4 base_color_factor;
    vec4 metallic_roughness_factor_pad2;
    vec4 emissive_factor_pad;
};

layout(set = 0, binding = 1) readonly buffer MaterialBuffer
{
    Material materials[];
} materialBuffer[];

layout(location = 0) in vec2 frag_uv0;
layout(location = 1) in vec2 frag_uv1;
layout(location = 2) flat in uint material_index;
layout(location = 3) in vec3 frag_norm;

layout(location = 0) out vec4 out_frag_color;

float map(float value, float min1, float max1, float min2, float max2) {
    return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}

void main()
{
    Material material = materialBuffer[getIndex(push_constants.material_binding)].materials[material_index];

    vec4 base_color = material.base_color_factor;

    if (material.base_color_texture != 0u)
    {
        base_color *= sampleTexture(push_constants.texture_info_binding, material.base_color_texture, frag_uv0);
    }

    // Basic "lighting" code
    // Just to add some depth to the scene
    const vec3 light_dir = normalize(vec3(-0.4, -1, -0.25));
    const float dot = max(dot(light_dir, -frag_norm), 0.0);
    const float light_amount = map(dot, 0.0, 1.0, 0.25, 1.0);

    out_frag_color = base_color * light_amount;

    // #ifdef ALPHA_CUTOFF
    // if (base_color.a < material.alpha_cutoff)
    // {
    //     discard;
    // }
    // #endif

    //out_frag_color = vec4(frag_uv0, 0.0, 1.0);
}
