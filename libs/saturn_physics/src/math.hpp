#pragma once

#include <Jolt/Jolt.h>

inline JPH::Float3 load_float3(const float float3[3]) {
  return {float3[0], float3[1], float3[2]};
}

static inline JPH::Vec3 load_vec3(const float in[3]) {
  return JPH::Vec3(*reinterpret_cast<const JPH::Float3 *>(in));
}

static inline JPH::RVec3 load_rvec3(const JPH::Real in[3]) {
  return JPH::RVec3(*reinterpret_cast<const JPH::Float3 *>(in));
}

static inline JPH::Vec4 load_vec4(const float in[4]) {
  return JPH::Vec4::sLoadFloat4(reinterpret_cast<const JPH::Float4 *>(in));
}

static inline JPH::Quat load_quat(const float in[4]) {
  return JPH::Quat(in[0], in[1], in[2], in[3]);
}
