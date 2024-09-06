#pragma once

#include <Jolt/Jolt.h>

#include "memory.hpp"
#include "saturn_jolt.h"
#include <Jolt/Physics/Character/CharacterVirtual.h>

class PhysicsWorld;

class Character : JPH::CharacterContactListener {
public:
  Character(PhysicsWorld *physics_world, JPH::RefConst<JPH::Shape> shape, const JPH::RVec3 position, const JPH::Quat rotation);

  ~Character() override;

  void update(PhysicsWorld *physics_world, float delta_time);

  virtual void
  OnContactAdded(const JPH::CharacterVirtual *inCharacter, const JPH::BodyID &inBodyID2, const JPH::SubShapeID &inSubShapeID2, JPH::RVec3Arg inContactPosition, JPH::Vec3Arg inContactNormal, JPH::CharacterContactSettings &ioSettings) override;

public:
  JPH::RefConst<JPH::Shape> shape;
  JPH::CharacterVirtual *character;
  JoltVector<JPH::BodyID> contact_bodies;
  JPH::Vec3 gravity_velocity;
};
