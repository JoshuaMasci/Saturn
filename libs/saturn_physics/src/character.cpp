#include "character.hpp"

#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>

#include "memory.hpp"
#include "physics_world.hpp"
#include "math.hpp"

Character::Character(PhysicsWorld *physics_world, JPH::RefConst<JPH::Shape> shape, const JPH::RVec3 position,
                     const JPH::Quat rotation) {

    this->shape = shape;

    JPH::CharacterVirtualSettings settings = JPH::CharacterVirtualSettings();
    settings.mShape = this->shape;
    settings.mMaxSlopeAngle = M_PI_4f;
    settings.mMaxStrength = 100.0f;
    settings.mBackFaceMode = JPH::EBackFaceMode::CollideWithBackFaces;
    settings.mCharacterPadding = 0.02f;
    settings.mPenetrationRecoverySpeed = 1.0f;
    settings.mPredictiveContactDistance = 0.1f;

    this->character = alloc_t<JPH::CharacterVirtual>();
    ::new(this->character) JPH::CharacterVirtual(&settings, position, rotation, 0,
                                                 physics_world->physics_system);

}

Character::~Character() {
    this->character->~CharacterVirtual();
    free_t(this->character);
}

void Character::update(PhysicsWorld *physics_world, float delta_time) {
    this->character->SetLinearVelocity(JPH::Vec3(0.0, -2.0, 0.0));

    this->character->Update(delta_time, JPH::Vec3::sZero(),
                            JPH::BroadPhaseLayerFilter(),
                            JPH::ObjectLayerFilter(), JPH::BodyFilter(), JPH::ShapeFilter(),
                            physics_world->temp_allocator);
}

