#pragma once

#include <Jolt/Jolt.h>

static inline JPH::Vec4 load_vec4(const float in[4]) {
    return JPH::Vec4::sLoadFloat4(reinterpret_cast<const JPH::Float4 *>(in));
}

static inline JPH::Vec3 load_vec3(const float in[3]) {
    return JPH::Vec3(*reinterpret_cast<const JPH::Float3 *>(in));
}

static inline JPH::RVec3 load_rvec3(const JPH::Real in[3]) {
    return JPH::RVec3(*reinterpret_cast<const JPH::Float3 *>(in));
}

static inline JPH::Quat load_quat(const float in[4]) {
    return JPH::Quat(in[0], in[1], in[2], in[3]);
}

static inline JPH::Quat rotation_between_vectors(const JPH::Vec3 &v0, const JPH::Vec3 &v1) {
    JPH::Vec3 v0_normalized = v0.Normalized();
    JPH::Vec3 v1_normalized = v1.Normalized();

    JPH::Vec3 cross_product = v0_normalized.Cross(v1_normalized).Normalized();
    float angle = acosf(v0_normalized.Dot(v1_normalized));

    if (!isnanf(angle) && angle != 0.0) {
        return JPH::Quat::sRotation(cross_product, angle);
    } else {
        return JPH::Quat::sIdentity();
    }
}