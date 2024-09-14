#include "character.hpp"

#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>

#include <utility>

#include "math.hpp"
#include "memory.hpp"
#include "physics_world.hpp"

Character::Character(PhysicsWorld *physics_world, JPH::RefConst<JPH::Shape> shape, JPH::RVec3 position,
                     JPH::Quat rotation, JPH::RefConst<JPH::Shape> inner_shape, ObjectLayer inner_object_layer) {
    this->shape = std::move(shape);
    this->inner_shape = std::move(inner_shape);

    JPH::CharacterVirtualSettings settings = JPH::CharacterVirtualSettings();
    settings.mShape = this->shape;
    settings.mMaxSlopeAngle = M_PI_4;
    settings.mMaxStrength = 100.0f;
    settings.mBackFaceMode = JPH::EBackFaceMode::CollideWithBackFaces;
    settings.mCharacterPadding = 0.02f;
    settings.mPenetrationRecoverySpeed = 1.0f;
    settings.mPredictiveContactDistance = 0.1f;

    if (this->inner_shape != nullptr) {
        settings.mInnerBodyShape = this->inner_shape;
        settings.mInnerBodyLayer = inner_object_layer;
    }

    this->character = alloc_t<JPH::CharacterVirtual>();
    ::new(this->character) JPH::CharacterVirtual(
            &settings, position, rotation, 0, physics_world->physics_system);
    this->character->SetListener(this);
    this->gravity_velocity = JPH::Vec3::sReplicate(0.0);
}

Character::~Character() {
    this->character->~CharacterVirtual();
    free_t(this->character);
}

void Character::update(PhysicsWorld *physics_world, float delta_time) {
    JPH::BodyID gravity_body;
    for (auto body_id: this->contact_bodies) {
        if (physics_world->volume_bodies.find(body_id) !=
            physics_world->volume_bodies.end()) {
            gravity_body = body_id;
        }
    }

    if (!gravity_body.IsInvalid()) {
        JPH::BodyInterface &body_interface =
                physics_world->physics_system->GetBodyInterface();
        auto volume_body = &physics_world->volume_bodies[gravity_body];

        if (volume_body->gravity_strength) {
            JPH::Real gravity_strength = volume_body->gravity_strength.value();
            JPH::RVec3 gravity_position = body_interface.GetPosition(gravity_body);
            JPH::RVec3 character_position = this->character->GetPosition();
            JPH::RVec3 difference = gravity_position - character_position;
            JPH::Real distance2 = difference.LengthSq();
            this->gravity_velocity =
                    difference.Normalized() * (gravity_strength / distance2);
            this->character->SetLinearVelocity(this->character->GetLinearVelocity() +
                                               (this->gravity_velocity * delta_time));
            auto current_rotation = this->character->GetRotation();
            auto current_up = current_rotation.RotateAxisY();
            auto new_up = (character_position - gravity_position).Normalized();
            this->character->SetUp(new_up);
            this->character->SetRotation(
                    (JPH::Quat::sFromTo(current_up, new_up) * current_rotation)
                            .Normalized());
        }
    }

    this->contact_bodies.clear();

    JPH::CharacterVirtual::ExtendedUpdateSettings update_settings;
    update_settings.mStickToFloorStepDown =
            this->character->GetRotation().RotateAxisY() * -0.4f;
    update_settings.mWalkStairsStepUp =
            this->character->GetRotation().RotateAxisY() * 0.25f;
    this->character->ExtendedUpdate(
            delta_time, this->gravity_velocity, update_settings, JPH::BroadPhaseLayerFilter(), JPH::ObjectLayerFilter(),
            JPH::BodyFilter(), JPH::ShapeFilter(), physics_world->temp_allocator);
}

void Character::OnContactAdded(const JPH::CharacterVirtual *inCharacter, const JPH::BodyID &inBodyID2,
                               const JPH::SubShapeID &inSubShapeID2, JPH::RVec3Arg inContactPosition,
                               JPH::Vec3Arg inContactNormal, JPH::CharacterContactSettings &ioSettings) {
    this->contact_bodies.push_back(inBodyID2);
}
