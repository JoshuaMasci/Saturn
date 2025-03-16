#include "callback_debug_renderer.hpp"

// Needed to make the casting from JPH to Saturn unambiguous for some reason
namespace Saturn {
	using Triangle = Triangle;
	using Vertex = Vertex;
} // namespace Saturn

CallbackDebugRenderer::CallbackDebugRenderer(DebugRendererData data) {
	callback_data = data;
	Initialize();
}

CallbackDebugRenderer::~CallbackDebugRenderer() {
}

void CallbackDebugRenderer::DrawLine(JPH::RVec3Arg inFrom, JPH::RVec3Arg inTo, JPH::ColorArg inColor) {
	if (callback_data.draw_line) {
		callback_data.draw_line(callback_data.ptr, &inFrom.mF32[0], &inTo.mF32[0], color_from_u32(inColor.mU32));
	}
}

void CallbackDebugRenderer::DrawTriangle(JPH::RVec3Arg inV1, JPH::RVec3Arg inV2, JPH::RVec3Arg inV3, JPH::ColorArg inColor, JPH::DebugRenderer::ECastShadow inCastShadow) {
	if (callback_data.draw_triangle) {
		callback_data.draw_triangle(callback_data.ptr, &inV1.mF32[0], &inV2.mF32[0], &inV3.mF32[0], color_from_u32(inColor.mU32));
	}
}

JPH::DebugRenderer::Batch CallbackDebugRenderer::CreateTriangleBatch(const JPH::DebugRenderer::Triangle *inTriangles, int inTriangleCount) {
	MeshPrimitive id = 0;
	if (callback_data.create_triangle_mesh) {
		callback_data.create_triangle_mesh(callback_data.ptr, id, (const Saturn::Triangle *)inTriangles, inTriangleCount);
	}
	return new CallbackRenderPrimitive(callback_data.ptr, callback_data.free_mesh, id);
}

JPH::DebugRenderer::Batch CallbackDebugRenderer::CreateTriangleBatch(const JPH::DebugRenderer::Vertex *inVertices, int inVertexCount, const JPH::uint32 *inIndices, int inIndexCount) {
	MeshPrimitive id = 0;
	if (callback_data.create_indexed_mesh) {
		callback_data.create_indexed_mesh(callback_data.ptr, id, (const Saturn::Vertex *)inVertices, inVertexCount, inIndices, inIndexCount);
	}
	return new CallbackRenderPrimitive(callback_data.ptr, callback_data.free_mesh, id);
}

void CallbackDebugRenderer::DrawGeometry(const JPH::Mat44 &inModelMatrix, const JPH::AABox &inWorldSpaceBounds, float inLODScaleSq, JPH::ColorArg inModelColor, const JPH::DebugRenderer::GeometryRef &inGeometry, JPH::DebugRenderer::ECullMode inCullMode, JPH::DebugRenderer::ECastShadow inCastShadow, JPH::DebugRenderer::EDrawMode inDrawMode) {
	if (callback_data.draw_geometry) {
		auto primitive = dynamic_cast<CallbackRenderPrimitive *>(inGeometry->mLODs[0].mTriangleBatch.GetPtr());
		callback_data.draw_geometry(callback_data.ptr, nullptr, color_from_u32(inModelColor.mU32), primitive->GetId()); // TODO: figure out lod
	}
}

void CallbackDebugRenderer::DrawText3D(JPH::RVec3Arg inPosition, const std::string_view &inString, JPH::ColorArg inColor, float inHeight) {
	if (callback_data.draw_text) {
		callback_data.draw_text(callback_data.ptr, &inPosition.mF32[0], const_cast<char *>(inString.data()), inString.size(), color_from_u32(inColor.mU32), inHeight);
	}
}
