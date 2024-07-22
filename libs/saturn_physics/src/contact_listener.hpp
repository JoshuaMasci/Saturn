#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Physics/PhysicsSystem.h>

class PhysicsWorld;

class MyContactListener : public JPH::ContactListener
{
public:
    MyContactListener(PhysicsWorld* physics_world);
    JPH::ValidateResult OnContactValidate(const JPH::Body &inBody1, const JPH::Body &inBody2, JPH::RVec3Arg inBaseOffset, const JPH::CollideShapeResult &inCollisionResult) override;
    void OnContactAdded(const JPH::Body &inBody1, const JPH::Body &inBody2, const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) override;
    void OnContactPersisted(const JPH::Body &inBody1, const JPH::Body &inBody2, const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) override;
    void OnContactRemoved(const JPH::SubShapeIDPair &inSubShapePair) override;
private:
    PhysicsWorld* physics_world = nullptr;
};