#include "callback_debug_renderer.hpp"

CallbackDebugRenderer::CallbackDebugRenderer() {
	callback_data = nullptr;
}

CallbackDebugRenderer::~CallbackDebugRenderer() {
}

void CallbackDebugRenderer::DrawLine(JPH::RVec3Arg inFrom, JPH::RVec3Arg inTo, JPH::ColorArg inColor) {
//	if (callback_data && callback_data->draw_line) {
//		callback_data->draw_line(callback_data->data, &inFrom.mF32[0], &inTo.mF32[0], inColor);
//	}
}

void CallbackDebugRenderer::DrawTriangle(JPH::RVec3Arg inV1, JPH::RVec3Arg inV2, JPH::RVec3Arg inV3, JPH::ColorArg inColor, JPH::DebugRenderer::ECastShadow inCastShadow) {
//	if (callback_data && callback_data->draw_triangle) {
//		callback_data->draw_triangle(callback_data->data, inV1, inV2, inV3, inColor);
//	}
}

JPH::DebugRenderer::Batch CallbackDebugRenderer::CreateTriangleBatch(const JPH::DebugRenderer::Triangle *inTriangles, int inTriangleCount) {
//	if (callback_data && callback_data->create_triangle_mesh) {
//		return callback_data->create_triangle_mesh(callback_data->data, reinterpret_cast<const Triangle *>(inTriangles), inTriangleCount);
//	}
	return JPH::DebugRenderer::Batch();
}

JPH::DebugRenderer::Batch CallbackDebugRenderer::CreateTriangleBatch(const JPH::DebugRenderer::Vertex *inVertices, int inVertexCount, const JPH::uint32 *inIndices, int inIndexCount) {
//	if (callback_data && callback_data->create_indexed_mesh) {
//		const Vertex * ptr = (const Vertex *)inVertices;
//		return callback_data->create_indexed_mesh(callback_data->data, ptr, inVertexCount, inIndices, inIndexCount);
//	}
	return JPH::DebugRenderer::Batch();
}

void CallbackDebugRenderer::DrawGeometry(const JPH::Mat44 &inModelMatrix, const JPH::AABox &inWorldSpaceBounds, float inLODScaleSq, JPH::ColorArg inModelColor, const JPH::DebugRenderer::GeometryRef &inGeometry, JPH::DebugRenderer::ECullMode inCullMode, JPH::DebugRenderer::ECastShadow inCastShadow, JPH::DebugRenderer::EDrawMode inDrawMode) {
//	if (callback_data && callback_data->draw_geometry) {
//		callback_data->draw_geometry(callback_data->data, inModelMatrix, inModelColor, inGeometry);
//	}
}

void CallbackDebugRenderer::DrawText3D(JPH::RVec3Arg inPosition, const std::string_view &inString, JPH::ColorArg inColor, float inHeight) {
//	if (callback_data && callback_data->draw_text) {
//		callback_data->draw_text(callback_data->data, inPosition, const_cast<char*>(inString.data()), inString.size(), inColor, inHeight);
//	}
}