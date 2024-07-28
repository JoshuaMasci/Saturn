#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Physics/Character/CharacterVirtual.h>

class PhysicsWorld;

class Character {
public:
    Character(PhysicsWorld *physics_world);

    ~Character();

    void update(PhysicsWorld *physics_world, float delta_time);


private:

    JPH::RefConst<JPH::Shape> shape;
    JPH::CharacterVirtual *character;
};