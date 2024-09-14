#pragma once

#include <Jolt/Jolt.h>

#include "memory.hpp"
#include "saturn_jolt.h"
#include <Jolt/Physics/Character/CharacterVirtual.h>

#include <utility>

class PhysicsWorld;

class Character : JPH::CharacterContactListener {
public:
    Character(PhysicsWorld *physics_world, JPH::RefConst<JPH::Shape> shape, JPH::RVec3 position, JPH::Quat rotation)
            : Character(physics_world, std::move(shape), position, rotation,
                        nullptr, 0) {}

    Character(PhysicsWorld *physics_world, JPH::RefConst<JPH::Shape> shape, JPH::RVec3 position, JPH::Quat rotation,
              JPH::RefConst<JPH::Shape> inner_shape, ObjectLayer inner_object_layer);

    ~Character() override;

    void update(PhysicsWorld *physics_world, float delta_time);

    virtual void
    OnContactAdded(const JPH::CharacterVirtual *inCharacter, const JPH::BodyID &inBodyID2,
                   const JPH::SubShapeID &inSubShapeID2, JPH::RVec3Arg inContactPosition, JPH::Vec3Arg inContactNormal,
                   JPH::CharacterContactSettings &ioSettings) override;

public:
    JPH::RefConst<JPH::Shape> shape;
    JPH::RefConst<JPH::Shape> inner_shape;

    JPH::CharacterVirtual *character;
    JoltVector<JPH::BodyID> contact_bodies;
    JPH::Vec3 gravity_velocity;
};
