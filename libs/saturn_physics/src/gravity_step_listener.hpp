#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsStepListener.h>

class PhysicsWorld;

class GravityStepListener : public JPH::PhysicsStepListener {
  public:
	GravityStepListener(PhysicsWorld *physics_world);

	virtual void OnStep(float inDeltaTime, JPH::PhysicsSystem &inPhysicsSystem) override;

  private:
	PhysicsWorld *physics_world = nullptr;
};
