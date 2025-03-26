#pragma once

#include <Jolt/Jolt.h>

inline JPH::Float3 loadFloat3(const float float3[3]) {
	return {float3[0], float3[1], float3[2]};
}

inline JPH::Vec3 loadVec3(const float in[3]) {
	return JPH::Vec3(*reinterpret_cast<const JPH::Float3 *>(in));
}

inline JPH::RVec3 loadRVec3(const JPH::Real in[3]) {
	return JPH::RVec3(*reinterpret_cast<const JPH::Real3 *>(in));
}

inline JPH::Vec4 loadVec4(const float in[4]) {
	return JPH::Vec4::sLoadFloat4(reinterpret_cast<const JPH::Float4 *>(in));
}

inline JPH::Quat loadQuat(const float in[4]) {
	return static_cast<JPH::Quat>(loadVec4(in));
}

inline void storeMat44(const JPH::Mat44 &inMatrix, Mat44 outMatrix) {
	for (int column = 0; column < 4; ++column) {
		auto columnVec = inMatrix.GetColumn4(column);
		outMatrix[column * 4 + 0] = columnVec[0];
		outMatrix[column * 4 + 1] = columnVec[1];
		outMatrix[column * 4 + 2] = columnVec[2];
		outMatrix[column * 4 + 3] = columnVec[3];
	}
}