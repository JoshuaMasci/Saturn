#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Physics/Character/CharacterVirtual.h>
#include "saturn_jolt.h"

class PhysicsWorld;

class Character {
public:
    Character(PhysicsWorld *physics_world, JPH::RefConst<JPH::Shape> shape, const JPH::RVec3 position,
              const JPH::Quat rotation);

    ~Character();

    void update(PhysicsWorld *physics_world, float delta_time);

public:

    JPH::RefConst<JPH::Shape> shape;
    JPH::CharacterVirtual *character;
};