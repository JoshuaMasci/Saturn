//Not actually PBR yet
#include "include/bindless.glsl"
#include "include/texture.glsl"
#include "include/material.glsl"

layout(set = 0, binding = 1) readonly buffer MaterialBuffer
{
    Material materials[];
} materialBuffer[];

struct FragData
{
    vec3 position;
    vec3 normal;
    vec2 uv0;
    vec2 uv1;
    uint material_index;
};

float map(float value, float min1, float max1, float min2, float max2) {
    return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}

vec4 calcColor(uint material_binding, uint texture_binding, FragData frag)
{
    Material material = materialBuffer[getIndex(material_binding)].materials[material_index];

    vec4 base_color = material.base_color_factor;

    if (material.base_color_texture != 0u)
    {
        base_color *= sampleTexture(texture_binding, material.base_color_texture, frag.uv0);
    }

    #ifdef ALPHA_CUTOFF
    if (base_color.a < material.alpha_cutoff)
    {
        discard;
    }
    base_color.a = 1.0;
    #endif

    // Basic "lighting" code
    // Just to add some depth to the scene
    const vec3 light_dir = normalize(vec3(-0.4, -1, -0.25));
    const float dot = max(dot(light_dir, -frag.normal), 0.0);
    const float light_amount = map(dot, 0.0, 1.0, 0.25, 1.0);

    return base_color * light_amount;
}
