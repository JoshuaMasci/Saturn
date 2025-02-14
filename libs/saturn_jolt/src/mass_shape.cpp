#include <Jolt/Jolt.h>

#include "Jolt/Physics/Collision/CollisionDispatch.h"
#include <Jolt/Core/StreamIn.h>
#include <Jolt/Core/StreamOut.h>
#include <Jolt/ObjectStream/TypeDeclarations.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/ShapeCast.h>
#include <Jolt/Physics/Collision/TransformedShape.h>
#include <mass_shape.hpp>

JPH_NAMESPACE_BEGIN

JPH_IMPLEMENT_SERIALIZABLE_VIRTUAL(MassShapeSettings)
	{
		JPH_ADD_BASE_CLASS(MassShapeSettings, DecoratedShapeSettings)

			JPH_ADD_ATTRIBUTE(MassShapeSettings, mScale)
	}

ShapeSettings::ShapeResult MassShapeSettings::Create() const
{
	if (mCachedResult.IsEmpty())
		Ref<Shape> shape = new MassShape(*this, mCachedResult);
	return mCachedResult;
}

MassShape::MassShape(const MassShapeSettings &inSettings, ShapeResult &outResult) :
																						  DecoratedShape(EShapeSubType::User1, inSettings, outResult),
																					mMassProperties(inSettings.mMassProperties)
{
	if (outResult.HasError())
		return;

	outResult.Set(this);
}

MassProperties MassShape::GetMassProperties() const
{
	return mMassProperties;
}

AABox MassShape::GetLocalBounds() const
{
	return mInnerShape->GetLocalBounds();
}

AABox MassShape::GetWorldSpaceBounds(Mat44Arg inCenterOfMassTransform, Vec3Arg inScale) const
{
	return mInnerShape->GetWorldSpaceBounds(inCenterOfMassTransform, inScale);
}

TransformedShape MassShape::GetSubShapeTransformedShape(const SubShapeID &inSubShapeID, Vec3Arg inPositionCOM, QuatArg inRotation, Vec3Arg inScale, SubShapeID &outRemainder) const
{
	// We don't use any bits in the sub shape ID
	outRemainder = inSubShapeID;

	TransformedShape ts(RVec3(inPositionCOM), inRotation, mInnerShape, BodyID());
	ts.SetShapeScale(inScale);
	return ts;
}

Vec3 MassShape::GetSurfaceNormal(const SubShapeID &inSubShapeID, Vec3Arg inLocalSurfacePosition) const
{
	return mInnerShape->GetSurfaceNormal(inSubShapeID, inLocalSurfacePosition);
}

void MassShape::GetSupportingFace(const SubShapeID &inSubShapeID, Vec3Arg inDirection, Vec3Arg inScale, Mat44Arg inCenterOfMassTransform, SupportingFace &outVertices) const
{
	mInnerShape->GetSupportingFace(inSubShapeID, inDirection, inScale, inCenterOfMassTransform, outVertices);
}

void MassShape::GetSubmergedVolume(Mat44Arg inCenterOfMassTransform, Vec3Arg inScale, const Plane &inSurface, float &outTotalVolume, float &outSubmergedVolume, Vec3 &outCenterOfBuoyancy JPH_IF_DEBUG_RENDERER(, RVec3Arg inBaseOffset)) const
{
	mInnerShape->GetSubmergedVolume(inCenterOfMassTransform, inScale, inSurface, outTotalVolume, outSubmergedVolume, outCenterOfBuoyancy JPH_IF_DEBUG_RENDERER(, inBaseOffset));
}

#ifdef JPH_DEBUG_RENDERER
void MassShape::Draw(DebugRenderer *inRenderer, RMat44Arg inCenterOfMassTransform, Vec3Arg inScale, ColorArg inColor, bool inUseMaterialColors, bool inDrawWireframe) const
{
	mInnerShape->Draw(inRenderer, inCenterOfMassTransform, inScale, inColor, inUseMaterialColors, inDrawWireframe);
}

void MassShape::DrawGetSupportFunction(DebugRenderer *inRenderer, RMat44Arg inCenterOfMassTransform, Vec3Arg inScale, ColorArg inColor, bool inDrawSupportDirection) const
{
	mInnerShape->DrawGetSupportFunction(inRenderer, inCenterOfMassTransform, inScale, inColor, inDrawSupportDirection);
}

void MassShape::DrawGetSupportingFace(DebugRenderer *inRenderer, RMat44Arg inCenterOfMassTransform, Vec3Arg inScale) const
{
	mInnerShape->DrawGetSupportingFace(inRenderer, inCenterOfMassTransform, inScale);
}
#endif // JPH_DEBUG_RENDERER

bool MassShape::CastRay(const RayCast &inRay, const SubShapeIDCreator &inSubShapeIDCreator, RayCastResult &ioHit) const
{
	return mInnerShape->CastRay(inRay, inSubShapeIDCreator, ioHit);
}

void MassShape::CastRay(const RayCast &inRay, const RayCastSettings &inRayCastSettings, const SubShapeIDCreator &inSubShapeIDCreator, CastRayCollector &ioCollector, const ShapeFilter &inShapeFilter) const
{
	// Test shape filter
	if (!inShapeFilter.ShouldCollide(this, inSubShapeIDCreator.GetID()))
		return;

	return mInnerShape->CastRay(inRay, inRayCastSettings, inSubShapeIDCreator, ioCollector, inShapeFilter);
}

void MassShape::CollidePoint(Vec3Arg inPoint, const SubShapeIDCreator &inSubShapeIDCreator, CollidePointCollector &ioCollector, const ShapeFilter &inShapeFilter) const
{
	// Test shape filter
	if (!inShapeFilter.ShouldCollide(this, inSubShapeIDCreator.GetID()))
		return;

	mInnerShape->CollidePoint(inPoint, inSubShapeIDCreator, ioCollector, inShapeFilter);
}

void MassShape::CollideSoftBodyVertices(Mat44Arg inCenterOfMassTransform, Vec3Arg inScale, const CollideSoftBodyVertexIterator &inVertices, uint inNumVertices, int inCollidingShapeIndex) const
{
	mInnerShape->CollideSoftBodyVertices(inCenterOfMassTransform, inScale, inVertices, inNumVertices, inCollidingShapeIndex);
}

void MassShape::CollectTransformedShapes(const AABox &inBox, Vec3Arg inPositionCOM, QuatArg inRotation, Vec3Arg inScale, const SubShapeIDCreator &inSubShapeIDCreator, TransformedShapeCollector &ioCollector, const ShapeFilter &inShapeFilter) const
{
	// Test shape filter
	if (!inShapeFilter.ShouldCollide(this, inSubShapeIDCreator.GetID()))
		return;

	mInnerShape->CollectTransformedShapes(inBox, inPositionCOM, inRotation, inScale, inSubShapeIDCreator, ioCollector, inShapeFilter);
}

void MassShape::TransformShape(Mat44Arg inCenterOfMassTransform, TransformedShapeCollector &ioCollector) const
{
	mInnerShape->TransformShape(inCenterOfMassTransform, ioCollector);
}

void MassShape::SaveBinaryState(StreamOut &inStream) const
{
	DecoratedShape::SaveBinaryState(inStream);

	inStream.Write(mMassProperties);
}

void MassShape::RestoreBinaryState(StreamIn &inStream)
{
	DecoratedShape::RestoreBinaryState(inStream);

	inStream.Read(mMassProperties);
}

float MassShape::GetVolume() const
{
	return mInnerShape->GetVolume();
}

bool MassShape::IsValidScale(Vec3Arg inScale) const
{
	return mInnerShape->IsValidScale(inScale);
}

Vec3 MassShape::MakeScaleValid(Vec3Arg inScale) const
{
	return mInnerShape->MakeScaleValid(inScale);
}
float MassShape::GetInnerRadius() const {
	return mInnerShape->GetInnerRadius();
}

void MassShape::sCollideMassVsShape(const Shape *inShape1, const Shape *inShape2, Vec3Arg inScale1, Vec3Arg inScale2, Mat44Arg inCenterOfMassTransform1, Mat44Arg inCenterOfMassTransform2, const SubShapeIDCreator &inSubShapeIDCreator1, const SubShapeIDCreator &inSubShapeIDCreator2, const CollideShapeSettings &inCollideShapeSettings, CollideShapeCollector &ioCollector, const ShapeFilter &inShapeFilter)
{
	JPH_ASSERT(inShape1->GetSubType() == EShapeSubType::User1);
	const MassShape *shape1 = static_cast<const MassShape *>(inShape1);
	CollisionDispatch::sCollideShapeVsShape(shape1->GetInnerShape(), inShape2, inScale1, inScale2, inCenterOfMassTransform1, inCenterOfMassTransform2, inSubShapeIDCreator1, inSubShapeIDCreator2, inCollideShapeSettings, ioCollector, inShapeFilter);
}

void MassShape::sCollideShapeVsMass(const Shape *inShape1, const Shape *inShape2, Vec3Arg inScale1, Vec3Arg inScale2, Mat44Arg inCenterOfMassTransform1, Mat44Arg inCenterOfMassTransform2, const SubShapeIDCreator &inSubShapeIDCreator1, const SubShapeIDCreator &inSubShapeIDCreator2, const CollideShapeSettings &inCollideShapeSettings, CollideShapeCollector &ioCollector, const ShapeFilter &inShapeFilter)
{
	JPH_ASSERT(inShape2->GetSubType() == EShapeSubType::User1);
	const MassShape *shape2 = static_cast<const MassShape *>(inShape2);
	CollisionDispatch::sCollideShapeVsShape(inShape1, shape2->GetInnerShape(), inScale1, inScale2, inCenterOfMassTransform1, inCenterOfMassTransform2, inSubShapeIDCreator1, inSubShapeIDCreator2, inCollideShapeSettings, ioCollector, inShapeFilter);
}

void MassShape::sCastMassVsShape(const ShapeCast &inShapeCast, const ShapeCastSettings &inShapeCastSettings, const Shape *inShape, Vec3Arg inScale, const ShapeFilter &inShapeFilter, Mat44Arg inCenterOfMassTransform2, const SubShapeIDCreator &inSubShapeIDCreator1, const SubShapeIDCreator &inSubShapeIDCreator2, CastShapeCollector &ioCollector)
{
	JPH_ASSERT(inShapeCast.mShape->GetSubType() == EShapeSubType::User1);
	const MassShape *shape = static_cast<const MassShape *>(inShapeCast.mShape);
	ShapeCast shape_cast(shape->GetInnerShape(), inShapeCast.mScale, inShapeCast.mCenterOfMassStart, inShapeCast.mDirection);
	CollisionDispatch::sCastShapeVsShapeLocalSpace(shape_cast, inShapeCastSettings, inShape, inScale, inShapeFilter, inCenterOfMassTransform2, inSubShapeIDCreator1, inSubShapeIDCreator2, ioCollector);
}

void MassShape::sCastShapeVsMass(const ShapeCast &inShapeCast, const ShapeCastSettings &inShapeCastSettings, const Shape *inShape, Vec3Arg inScale, const ShapeFilter &inShapeFilter, Mat44Arg inCenterOfMassTransform2, const SubShapeIDCreator &inSubShapeIDCreator1, const SubShapeIDCreator &inSubShapeIDCreator2, CastShapeCollector &ioCollector)
{
	JPH_ASSERT(inShapeCast.mShape->GetSubType() == EShapeSubType::User1);
	const MassShape *shape = static_cast<const MassShape *>(inShape);
	CollisionDispatch::sCastShapeVsShapeLocalSpace(inShapeCast, inShapeCastSettings, shape->mInnerShape, inScale, inShapeFilter, inCenterOfMassTransform2, inSubShapeIDCreator1, inSubShapeIDCreator2, ioCollector);
}

void MassShape::sRegister()
{
	ShapeFunctions &f = ShapeFunctions::sGet(EShapeSubType::User1);
	f.mConstruct = []() -> Shape * { return new MassShape; };
	f.mColor = Color::sYellow;

	for (EShapeSubType s : sAllSubShapeTypes)
	{
		CollisionDispatch::sRegisterCollideShape(EShapeSubType::User1, s, sCollideMassVsShape);
		CollisionDispatch::sRegisterCollideShape(s, EShapeSubType::User1, sCollideShapeVsMass);
		CollisionDispatch::sRegisterCastShape(EShapeSubType::User1, s, sCastMassVsShape);
		CollisionDispatch::sRegisterCastShape(s, EShapeSubType::User1, sCastShapeVsMass);
	}
}

JPH_NAMESPACE_END
