#ifndef BINDLESS_SET_INDEX
#define BINDLESS_SET_INDEX 0
#endif

// Binding 0: Uniform Buffers
// [[vk::binding(0, BINDLESS_SET_INDEX)]]
// cbuffer BindlessUniformBuffers[] : register(b0, space0)
// {
//     float4x4 dummy;
// };

// Binding 1: Storage Buffers
[[vk::binding(1, BINDLESS_SET_INDEX)]]
StructuredBuffer<float4> BindlessStorageBuffers[] : register(t1, space0);

// Binding 2: Sampled Images
[[vk::binding(2, BINDLESS_SET_INDEX)]]
SamplerState BindlessSamplers[] : register(s2, space0);
[[vk::binding(2, BINDLESS_SET_INDEX)]]
Texture2D BindlessTextures[] : register(t2, space0);

float4 sampleTexture(uint index, float2 uv)
{
    return BindlessTextures[index].Sample(BindlessSamplers[index], uv);
}

// Binding 3: Storage Images
[[vk::binding(3, BINDLESS_SET_INDEX)]]
RWTexture2D<float4> BindlessStorageImages[] : register(u3, space0);
