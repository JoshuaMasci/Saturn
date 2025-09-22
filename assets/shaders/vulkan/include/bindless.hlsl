#ifndef BINDLESS_SET_INDEX
#define BINDLESS_SET_INDEX 0
#endif

// Binding 0: Uniform Buffers
// #define UniformBufferArray(Type, Name) \
//     [[vk::binding(0, BINDLESS_SET_INDEX)]] ConstantBuffer<Type> Name[] : register(t0, space0);

// Binding 1: Storage Buffers
#define ReadOnlyStorageBufferArray(Type, Name) \
    [[vk::binding(1, BINDLESS_SET_INDEX)]] StructuredBuffer<Type> Name[];

#define ReadWriteStorageBufferArray(Type, Name) \
    [[vk::binding(1, BINDLESS_SET_INDEX)]] RWStructuredBuffer<Type> Name[];

[[vk::binding(1, BINDLESS_SET_INDEX)]]
ByteAddressBuffer storage_buffers[];

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
Texture2D<float4> ReadOnlyStorageImages[];

[[vk::binding(3, BINDLESS_SET_INDEX)]]
RWTexture2D<float4> ReadWriteStorageImages[];
