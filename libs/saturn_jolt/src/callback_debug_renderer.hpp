#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Core/Color.h>
#include <Jolt/Core/Reference.h>
#include <Jolt/Renderer/DebugRenderer.h>

#include "saturn_jolt.h"

class CallbackRenderPrimitive : public JPH::RefTarget<CallbackRenderPrimitive>, public JPH::RefTargetVirtual {
  public:
	CallbackRenderPrimitive(void *data, FreeMeshPrimitive free_fn, MeshPrimitive id) : data(data), free_fn(free_fn), id(id) {}
	~CallbackRenderPrimitive() override {
		if (this->free_fn) this->free_fn(data, id);
	};

	void AddRef() override { JPH::RefTarget<CallbackRenderPrimitive>::AddRef(); };
	void Release() override { JPH::RefTarget<CallbackRenderPrimitive>::Release(); };

	MeshPrimitive GetId() { return this->id; }

  private:
	void *data;
	FreeMeshPrimitive free_fn;
	MeshPrimitive id;
};

class CallbackDebugRenderer : public JPH::DebugRenderer {
  public:
	explicit CallbackDebugRenderer(DebugRendererData data);
	~CallbackDebugRenderer() override;
	void DrawLine(JPH::RVec3Arg inFrom, JPH::RVec3Arg inTo, JPH::ColorArg inColor) override;
	void DrawTriangle(JPH::RVec3Arg inV1, JPH::RVec3Arg inV2, JPH::RVec3Arg inV3, JPH::ColorArg inColor, ECastShadow inCastShadow) override;
	Batch CreateTriangleBatch(const Triangle *inTriangles, int inTriangleCount) override;
	Batch CreateTriangleBatch(const Vertex *inVertices, int inVertexCount, const JPH::uint32 *inIndices, int inIndexCount) override;
	void DrawGeometry(const JPH::Mat44 &inModelMatrix, const JPH::AABox &inWorldSpaceBounds, float inLODScaleSq, JPH::ColorArg inModelColor, const GeometryRef &inGeometry, ECullMode inCullMode, ECastShadow inCastShadow, EDrawMode inDrawMode) override;
	void DrawText3D(JPH::RVec3Arg inPosition, const std::string_view &inString, JPH::ColorArg inColor, float inHeight) override;

  protected:
	DebugRendererData callback_data;
};

constexpr bool validate_compatible_structs() {
	// Check Vertex compatibility
	static_assert(sizeof(Vertex) == sizeof(JPH::DebugRenderer::Vertex),
				  "Vertex struct sizes don't match");

	static_assert(alignof(Vertex) == alignof(JPH::DebugRenderer::Vertex),
				  "Vertex struct alignments don't match");

	static_assert(offsetof(Vertex, position) == offsetof(JPH::DebugRenderer::Vertex, mPosition),
				  "Position field offset mismatch");

	static_assert(offsetof(Vertex, normal) == offsetof(JPH::DebugRenderer::Vertex, mNormal),
				  "Normal field offset mismatch");

	static_assert(offsetof(Vertex, uv) == offsetof(JPH::DebugRenderer::Vertex, mUV),
				  "UV field offset mismatch");

	static_assert(offsetof(Vertex, color) == offsetof(JPH::DebugRenderer::Vertex, mColor),
				  "Color field offset mismatch");

	// Check Color struct compatibility
	static_assert(sizeof(Color) == sizeof(JPH::Color),
				  "Color struct sizes don't match");

	static_assert(alignof(Color) == alignof(JPH::Color),
				  "Color struct alignments don't match");

	static_assert(offsetof(Color, r) == offsetof(JPH::Color, r),
				  "Color r field offset mismatch");

	static_assert(offsetof(Color, g) == offsetof(JPH::Color, g),
				  "Color g field offset mismatch");

	static_assert(offsetof(Color, b) == offsetof(JPH::Color, b),
				  "Color b field offset mismatch");

	static_assert(offsetof(Color, a) == offsetof(JPH::Color, a),
				  "Color a field offset mismatch");

	// Check Triangle compatibility
	static_assert(sizeof(Triangle) == sizeof(JPH::DebugRenderer::Triangle),
				  "Triangle struct sizes don't match");

	static_assert(alignof(Triangle) == alignof(JPH::DebugRenderer::Triangle),
				  "Triangle struct alignments don't match");

	// Check memory layout of triangles
	// This checks that the vertex array layout matches between the two structs
	constexpr size_t triangle_vertex_stride = sizeof(Vertex);
	constexpr size_t jph_triangle_vertex_stride = sizeof(JPH::DebugRenderer::Vertex);
	static_assert(triangle_vertex_stride == jph_triangle_vertex_stride,
				  "Triangle vertex stride mismatch");

	// Check that the layout of vertices in the triangles matches
	static_assert(offsetof(JPH::DebugRenderer::Triangle, mV) == 0,
				  "JPH Triangle vertex array does not start at offset 0");

	return true;
}
static_assert(validate_compatible_structs(), "Struct compatibility validation failed");
