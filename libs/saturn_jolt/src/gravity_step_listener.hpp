#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsStepListener.h>

class PhysicsWorld;

class GravityStepListener : public JPH::PhysicsStepListener {
public:
    GravityStepListener(PhysicsWorld *physics_world);

    void OnStep(const JPH::PhysicsStepListenerContext &inContext) override;

private:
    PhysicsWorld *physics_world = nullptr;
};
