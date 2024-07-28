#include "character.hpp"

#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>

#include "memory.hpp"
#include "physics_world.hpp"

Character::Character(PhysicsWorld *physics_world) {
    float height = 1.8;
    float radius = 0.3;
    float cylinder_half_height = height - radius / 2.0f;

    auto shape_settings = JPH::CapsuleShapeSettings();
    shape_settings.mHalfHeightOfCylinder = cylinder_half_height;
    shape_settings.mRadius = radius;

    this->shape = shape_settings.Create().Get();

    JPH::CharacterVirtualSettings settings = JPH::CharacterVirtualSettings();
    settings.mShape = this->shape;
    settings.mMaxSlopeAngle = M_PI_4f;
    settings.mMaxStrength = 100.0f;
    settings.mBackFaceMode = JPH::EBackFaceMode::CollideWithBackFaces;
    settings.mCharacterPadding = 0.02f;
    settings.mPenetrationRecoverySpeed = 1.0f;
    settings.mPredictiveContactDistance = 0.1f;

    this->character = alloc_t<JPH::CharacterVirtual>();
    ::new(this->character) JPH::CharacterVirtual(&settings, JPH::RVec3::sZero(), JPH::Quat::sIdentity(), 0,
                                                 physics_world->physics_system);
}

Character::~Character() {
    this->character->~CharacterVirtual();
    free_t(this->character);
}

void Character::update(PhysicsWorld *physics_world, float delta_time) {
    this->character->Update(delta_time, JPH::Vec3::sZero(),
                            JPH::BroadPhaseLayerFilter(),
                            JPH::ObjectLayerFilter(), JPH::BodyFilter(), JPH::ShapeFilter(),
                            physics_world->temp_allocator);
}

