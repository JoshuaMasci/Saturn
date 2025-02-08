#pragma once

#include "Jolt/Physics/Collision/Shape/DecoratedShape.h"
#include <Jolt/Jolt.h>

JPH_NAMESPACE_BEGIN

class SubShapeIDCreator;
class CollideShapeSettings;

/// Class that constructs a MassShape
class JPH_EXPORT MassShapeSettings final : public DecoratedShapeSettings {
	JPH_DECLARE_SERIALIZABLE_VIRTUAL(JPH_EXPORT, MassShapeSettings)

  public:
	/// Default constructor for deserialization
	MassShapeSettings() = default;

	MassShapeSettings(const ShapeSettings *inShape, JPH::MassProperties massProperties) : DecoratedShapeSettings(inShape), mMassProperties(massProperties) {}
	MassShapeSettings(const Shape *inShape, JPH::MassProperties massProperties) : DecoratedShapeSettings(inShape), mMassProperties(massProperties) {}

	// See: ShapeSettings
	virtual ShapeResult Create() const override;

	JPH::MassProperties mMassProperties;
};

class JPH_EXPORT MassShape final : public DecoratedShape {
  public:
	JPH_OVERRIDE_NEW_DELETE

	/// Constructor
	MassShape() : DecoratedShape(EShapeSubType::User1) {}
	MassShape(const MassShapeSettings &inSettings, ShapeResult &outResult);

	MassShape(const Shape *inShape, JPH::MassProperties massProperties) : DecoratedShape(EShapeSubType::User1, inShape), mMassProperties(massProperties) {}

	virtual Vec3 GetCenterOfMass() const override { return mInnerShape->GetCenterOfMass(); }

	virtual AABox GetLocalBounds() const override;

	virtual AABox GetWorldSpaceBounds(Mat44Arg inCenterOfMassTransform, Vec3Arg inScale) const override;
	using Shape::GetWorldSpaceBounds;

	// See Shape::GetMassProperties
	virtual MassProperties GetMassProperties() const override;

	// See Shape::GetSubShapeTransformedShape
	virtual TransformedShape GetSubShapeTransformedShape(const SubShapeID &inSubShapeID, Vec3Arg inPositionCOM, QuatArg inRotation, Vec3Arg inScale, SubShapeID &outRemainder) const override;

	// See Shape::GetSurfaceNormal
	virtual Vec3 GetSurfaceNormal(const SubShapeID &inSubShapeID, Vec3Arg inLocalSurfacePosition) const override;

	// See Shape::GetSupportingFace
	virtual void GetSupportingFace(const SubShapeID &inSubShapeID, Vec3Arg inDirection, Vec3Arg inScale, Mat44Arg inCenterOfMassTransform, SupportingFace &outVertices) const override;

	// See Shape::GetSubmergedVolume
	virtual void GetSubmergedVolume(Mat44Arg inCenterOfMassTransform, Vec3Arg inScale, const Plane &inSurface, float &outTotalVolume, float &outSubmergedVolume, Vec3 &outCenterOfBuoyancy JPH_IF_DEBUG_RENDERER(, RVec3Arg inBaseOffset)) const override;

#ifdef JPH_DEBUG_RENDERER
	// See Shape::Draw
	virtual void Draw(DebugRenderer *inRenderer, RMat44Arg inCenterOfMassTransform, Vec3Arg inScale, ColorArg inColor, bool inUseMaterialColors, bool inDrawWireframe) const override;

	// See Shape::DrawGetSupportFunction
	virtual void DrawGetSupportFunction(DebugRenderer *inRenderer, RMat44Arg inCenterOfMassTransform, Vec3Arg inScale, ColorArg inColor, bool inDrawSupportDirection) const override;

	// See Shape::DrawGetSupportingFace
	virtual void DrawGetSupportingFace(DebugRenderer *inRenderer, RMat44Arg inCenterOfMassTransform, Vec3Arg inScale) const override;
#endif // JPH_DEBUG_RENDERER

	// See Shape::CastRay
	virtual bool CastRay(const RayCast &inRay, const SubShapeIDCreator &inSubShapeIDCreator, RayCastResult &ioHit) const override;
	virtual void CastRay(const RayCast &inRay, const RayCastSettings &inRayCastSettings, const SubShapeIDCreator &inSubShapeIDCreator, CastRayCollector &ioCollector, const ShapeFilter &inShapeFilter = {}) const override;

	// See: Shape::CollidePoint
	virtual void CollidePoint(Vec3Arg inPoint, const SubShapeIDCreator &inSubShapeIDCreator, CollidePointCollector &ioCollector, const ShapeFilter &inShapeFilter = {}) const override;

	// See: Shape::CollideSoftBodyVertices
	virtual void CollideSoftBodyVertices(Mat44Arg inCenterOfMassTransform, Vec3Arg inScale, const CollideSoftBodyVertexIterator &inVertices, uint inNumVertices, int inCollidingShapeIndex) const override;

	virtual void CollectTransformedShapes(const AABox &inBox, Vec3Arg inPositionCOM, QuatArg inRotation, Vec3Arg inScale, const SubShapeIDCreator &inSubShapeIDCreator, TransformedShapeCollector &ioCollector, const ShapeFilter &inShapeFilter) const override;

	// See Shape::TransformShape
	virtual void TransformShape(Mat44Arg inCenterOfMassTransform, TransformedShapeCollector &ioCollector) const override;

	// See Shape::GetTrianglesStart
	virtual void GetTrianglesStart(GetTrianglesContext &ioContext, const AABox &inBox, Vec3Arg inPositionCOM, QuatArg inRotation, Vec3Arg inScale) const override { JPH_ASSERT(false, "Cannot call on non-leaf shapes, use CollectTransformedShapes to collect the leaves first!"); }

	// See Shape::GetTrianglesNext
	virtual int GetTrianglesNext(GetTrianglesContext &ioContext, int inMaxTrianglesRequested, Float3 *outTriangleVertices, const PhysicsMaterial **outMaterials = nullptr) const override {
		JPH_ASSERT(false, "Cannot call on non-leaf shapes, use CollectTransformedShapes to collect the leaves first!");
		return 0;
	}

	// See Shape
	virtual void SaveBinaryState(StreamOut &inStream) const override;

	// See Shape::GetStats
	virtual Stats GetStats() const override { return Stats(sizeof(*this), 0); }

	// See Shape::GetVolume
	virtual float GetVolume() const override;

	// See Shape::IsValidScale
	virtual bool IsValidScale(Vec3Arg inScale) const override;

	// See Shape::MakeScaleValid
	virtual Vec3 MakeScaleValid(Vec3Arg inScale) const override;

	// See: Shape::GetInnerRadius
	float GetInnerRadius() const override;

	// Register shape functions with the registry
	static void sRegister();

  protected:
	// See: Shape::RestoreBinaryState
	virtual void RestoreBinaryState(StreamIn &inStream) override;

  private:
	// Helper functions called by CollisionDispatch
	static void sCollideMassVsShape(const Shape *inShape1, const Shape *inShape2, Vec3Arg inScale1, Vec3Arg inScale2, Mat44Arg inCenterOfMassTransform1, Mat44Arg inCenterOfMassTransform2, const SubShapeIDCreator &inSubShapeIDCreator1, const SubShapeIDCreator &inSubShapeIDCreator2, const CollideShapeSettings &inCollideShapeSettings, CollideShapeCollector &ioCollector, const ShapeFilter &inShapeFilter);
	static void sCollideShapeVsMass(const Shape *inShape1, const Shape *inShape2, Vec3Arg inScale1, Vec3Arg inScale2, Mat44Arg inCenterOfMassTransform1, Mat44Arg inCenterOfMassTransform2, const SubShapeIDCreator &inSubShapeIDCreator1, const SubShapeIDCreator &inSubShapeIDCreator2, const CollideShapeSettings &inCollideShapeSettings, CollideShapeCollector &ioCollector, const ShapeFilter &inShapeFilter);
	static void sCastMassVsShape(const ShapeCast &inShapeCast, const ShapeCastSettings &inShapeCastSettings, const Shape *inShape, Vec3Arg inScale, const ShapeFilter &inShapeFilter, Mat44Arg inCenterOfMassTransform2, const SubShapeIDCreator &inSubShapeIDCreator1, const SubShapeIDCreator &inSubShapeIDCreator2, CastShapeCollector &ioCollector);
	static void sCastShapeVsMass(const ShapeCast &inShapeCast, const ShapeCastSettings &inShapeCastSettings, const Shape *inShape, Vec3Arg inScale, const ShapeFilter &inShapeFilter, Mat44Arg inCenterOfMassTransform2, const SubShapeIDCreator &inSubShapeIDCreator1, const SubShapeIDCreator &inSubShapeIDCreator2, CastShapeCollector &ioCollector);

	JPH::MassProperties mMassProperties;
};

JPH_NAMESPACE_END