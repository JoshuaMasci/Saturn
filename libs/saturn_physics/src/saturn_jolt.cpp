#include "saturn_jolt.h"

#include <iostream>

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/MutableCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>

#include "memory.hpp"
#include "physics_world.hpp"
#include "math.hpp"
#include "character.hpp"

typedef JoltVector<JPH::ShapeRefC> ShapePool;
ShapePool *shape_pool = nullptr;

void SPH_Init(const SPH_AllocationFunctions *functions) {
    if (functions != nullptr) {
        JPH::Allocate = functions->alloc;
        JPH::Free = functions->free;
        JPH::AlignedAllocate = functions->aligned_alloc;
        JPH::AlignedFree = functions->aligned_free;
    } else {
        JPH::RegisterDefaultAllocator();
    }

    auto factory = static_cast<JPH::Factory *>(JPH::Allocate(sizeof(JPH::Factory)));
    ::new(factory) JPH::Factory();
    JPH::Factory::sInstance = factory;
    JPH::RegisterTypes();

    shape_pool = alloc_t<ShapePool>();
    ::new(shape_pool) ShapePool();
}

void SPH_Deinit() {
    shape_pool->~ShapePool();
    free_t(shape_pool);

    JPH::UnregisterTypes();
    JPH::Factory::sInstance->~Factory();
    JPH::Free((void *) JPH::Factory::sInstance);
    JPH::Factory::sInstance = nullptr;

    JPH::Allocate = nullptr;
    JPH::Free = nullptr;
    JPH::AlignedAllocate = nullptr;
    JPH::AlignedFree = nullptr;
}

SPH_ShapeHandle SPH_Shape_Sphere(float radius, float density) {
    auto settings = JPH::SphereShapeSettings();
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    auto index = shape_pool->size();
    shape_pool->emplace_back(shape);
    return index;
}

SPH_ShapeHandle SPH_Shape_Box(const float half_extent[3], float density) {
    auto settings = JPH::BoxShapeSettings();
    settings.mHalfExtent = load_vec3(half_extent);
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    auto index = shape_pool->size();
    shape_pool->emplace_back(shape);
    return index;
}

SPH_ShapeHandle SPH_Shape_Cylinder(float half_height, float radius, float density) {
    auto settings = JPH::CylinderShapeSettings();
    settings.mHalfHeight = half_height;
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    auto index = shape_pool->size();
    shape_pool->emplace_back(shape);
    return index;
}

SPH_ShapeHandle SPH_Shape_Capsule(float half_height, float radius, float density) {
    auto settings = JPH::CapsuleShapeSettings();
    settings.mHalfHeightOfCylinder = half_height;
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    auto index = shape_pool->size();
    shape_pool->emplace_back(shape);
    return index;
}

void SPH_Shape_Destroy(SPH_ShapeHandle handle) {
    // shape_pool->remove(ShapePool::Handle::from_u64(handle));
}

SPH_PhysicsWorld *SPH_PhysicsWorld_Create(const SPH_PhysicsWorldSettings *settings) {
    auto physics_world = alloc_t<PhysicsWorld>();
    ::new(physics_world) PhysicsWorld(settings);
    return (SPH_PhysicsWorld *) physics_world;
}

void SPH_PhysicsWorld_Destroy(SPH_PhysicsWorld *ptr) {
    auto physics_world = (PhysicsWorld *) ptr;
    physics_world->~PhysicsWorld();
    free_t(physics_world);
}

void SPH_PhysicsWorld_Update(SPH_PhysicsWorld *ptr, float delta_time, int collision_steps) {
    auto physics_world = (PhysicsWorld *) ptr;
    physics_world->update(delta_time, collision_steps);
}

SPH_BodyHandle SPH_PhysicsWorld_Body_Create(SPH_PhysicsWorld *ptr, const SPH_BodySettings *body_settings) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto shape = (*shape_pool)[body_settings->shape];
    auto position = load_vec3(body_settings->position);
    auto rotation = load_quat(body_settings->rotation);
    auto linear_velocity = load_vec3(body_settings->linear_velocity);
    auto angular_velocity = load_vec3(body_settings->angular_velocity);
    auto settings = JPH::BodyCreationSettings();
    settings.SetShape(shape);
    settings.mPosition = position;
    settings.mRotation = rotation;
    settings.mLinearVelocity = linear_velocity;
    settings.mAngularVelocity = angular_velocity;
    settings.mUserData = body_settings->user_data;

    switch (body_settings->motion_type) {
        case 0:
            settings.mMotionType = JPH::EMotionType::Static;
            settings.mObjectLayer = Layers::NON_MOVING;
            break;
        case 1:
            settings.mMotionType = JPH::EMotionType::Kinematic;
            settings.mObjectLayer = Layers::MOVING;
            break;
        case 2:
            settings.mMotionType = JPH::EMotionType::Dynamic;
            settings.mObjectLayer = Layers::MOVING;
            break;
    }

    settings.mIsSensor = body_settings->is_sensor;
    settings.mAllowSleeping = body_settings->allow_sleep;
    settings.mFriction = body_settings->friction;
    settings.mGravityFactor = body_settings->gravity_factor;
    settings.mLinearDamping = body_settings->linear_damping;
    settings.mAngularDamping = body_settings->angular_damping;

    JPH::BodyInterface &body_interface = physics_world->physics_system->GetBodyInterface();
    JPH::BodyID body_id = body_interface.CreateAndAddBody(settings, JPH::EActivation::Activate);

    if (body_settings->is_sensor) {
        physics_world->volume_bodies.emplace(body_id, VolumeBody());
    }

    return body_id.GetIndexAndSequenceNumber();
}

void SPH_PhysicsWorld_Body_Destroy(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface = physics_world->physics_system->GetBodyInterface();

    physics_world->volume_bodies.erase(body_id);

    body_interface.RemoveBody(body_id);
    body_interface.DestroyBody(body_id);
}

SPH_Transform SPH_PhysicsWorld_Body_GetTransform(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface = physics_world->physics_system->GetBodyInterface();
    JPH::RVec3 position;
    JPH::Quat rotation;
    body_interface.GetPositionAndRotation(body_id, position, rotation);
    return SPH_Transform{
            {position.GetX(), position.GetY(), position.GetZ()},
            {rotation.GetX(), rotation.GetY(), rotation.GetZ(), rotation.GetW()}};
}

void SPH_PhysicsWorld_Body_SetLinearVelocity(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle, const float velocity[3]) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface = physics_world->physics_system->GetBodyInterface();
    auto linear_velocity = load_vec3(velocity);
    body_interface.SetLinearVelocity(body_id, linear_velocity);
}


SPH_BodyHandleList SPH_PhysicsWorld_Body_GetContactList(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    if (physics_world->volume_bodies.find(body_id) != physics_world->volume_bodies.end()) {
        auto contact_list_ref = &physics_world->volume_bodies[body_id].contact_list;
        return SPH_BodyHandleList{
                reinterpret_cast<SPH_BodyHandle *>(contact_list_ref->get_ptr()), contact_list_ref->size()
        };

    } else {
        return SPH_BodyHandleList{
                nullptr, 0
        };
    }
}

void SPH_PhysicsWorld_Body_AddRadialGravity(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle, float gravity_strength) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    if (physics_world->volume_bodies.find(body_id) != physics_world->volume_bodies.end()) {
        if (gravity_strength != 0.0) {
            physics_world->volume_bodies[body_id].gravity_strength = gravity_strength;
        } else {
            physics_world->volume_bodies[body_id].gravity_strength.reset();
        }
    }
}

SPH_CharacterHandle
SPH_PhysicsWorld_Character_Add(SPH_PhysicsWorld *ptr, SPH_ShapeHandle shape, const SPH_Transform *transform) {
    auto shape_ref = (*shape_pool)[shape];
    auto physics_world = (PhysicsWorld *) ptr;
    return physics_world->add_character(shape_ref, load_rvec3(transform->position), load_quat(transform->rotation));
}

void SPH_PhysicsWorld_Character_Remove(SPH_PhysicsWorld *ptr, SPH_CharacterHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    physics_world->remove_character(handle);
}

SPH_Transform SPH_PhysicsWorld_Character_GetTransform(SPH_PhysicsWorld *ptr, SPH_CharacterHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];

    SPH_Transform transform;
    character->character->GetPosition().StoreFloat3(reinterpret_cast<JPH::Real3 *>(transform.position));
    character->character->GetRotation().GetXYZW().StoreFloat4(reinterpret_cast<JPH::Float4 *>(transform.rotation));
    return transform;
}

SPH_GroundState SPH_PhysicsWorld_Character_GetGroundState(SPH_PhysicsWorld *ptr, SPH_CharacterHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];

    SPH_GroundState ground_state;
    switch (character->character->GetGroundState()) {
        case JPH::CharacterBase::EGroundState::OnGround:
            ground_state = 0;
            break;
        case JPH::CharacterBase::EGroundState::OnSteepGround:
            ground_state = 1;
            break;
        case JPH::CharacterBase::EGroundState::InAir:
            ground_state = 2;
            break;
        case JPH::CharacterBase::EGroundState::NotSupported:
            ground_state = 3;
            break;
    }
    return ground_state;
}
