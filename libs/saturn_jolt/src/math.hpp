#pragma once

#include <Jolt/Jolt.h>

inline JPH::Float3 load_float3(const float float3[3]) {
	return {float3[0], float3[1], float3[2]};
}

inline JPH::Vec3 load_vec3(const float in[3]) {
	return JPH::Vec3(*reinterpret_cast<const JPH::Float3 *>(in));
}

inline JPH::RVec3 load_rvec3(const JPH::Real in[3]) {
	return JPH::RVec3(*reinterpret_cast<const JPH::Real3 *>(in));
}

inline JPH::Vec4 load_vec4(const float in[4]) {
	return JPH::Vec4::sLoadFloat4(reinterpret_cast<const JPH::Float4 *>(in));
}

inline JPH::Quat load_quat(const float in[4]) {
	return static_cast<JPH::Quat>(load_vec4(in));
}

inline void storeMat44(const JPH::Mat44 &inMatrix, Mat44 outMatrix) {
	for (int column = 0; column < 4; ++column) {
		for (int row = 0; row < 4; ++row) {
			outMatrix[row][column] = inMatrix.GetColumn4(column)[row];
		}
	}
}