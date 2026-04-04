#ifndef TEXTURE
#define TEXTURE

#include "include/bindless.glsl"
#include "include/debug.glsl"

layout(set = 0, binding = 2) uniform sampler2D BindlessTextures[];

struct TextureInfo
{
    uint loaded;
    uint sampled_binding;
    uint width;
    uint height;
    uint depth;
    uint mip_count;
    uint format;
    uint _padding;
};

layout(set = 0, binding = 1) readonly buffer TextureInfoBuffer
{
    TextureInfo info[];
} textureInfo[];

vec4 sampleTexture(uint info_binding, uint index, vec2 uv)
{
    TextureInfo info = textureInfo[getIndex(info_binding)].info[index];
    if (info.loaded != 0) {
        return texture(BindlessTextures[getIndex(info.sampled_binding)], uv);
    }
    return vec4(0.0);
}

#endif
