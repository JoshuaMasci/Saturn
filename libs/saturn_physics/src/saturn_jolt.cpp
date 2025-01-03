#include "saturn_jolt.h"

#include <cstdio>
#include <iostream>

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/MutableCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/RayCast.h>

#include "collision_collector.hpp"
#include "character.hpp"
#include "layer_filters.hpp"
#include "math.hpp"
#include "memory.hpp"
#include "physics_world.hpp"
#include "shape_pool.hpp"

ShapePool *shape_pool = nullptr;

void init(const AllocationFunctions *functions) {
    if (functions != nullptr) {
        JPH::Allocate = functions->alloc;
        JPH::Free = functions->free;
        JPH::AlignedAllocate = functions->aligned_alloc;
        JPH::AlignedFree = functions->aligned_free;
        JPH::Reallocate = functions->realloc;
    } else {
        JPH::RegisterDefaultAllocator();
    }

    auto factory =
            static_cast<JPH::Factory *>(JPH::Allocate(sizeof(JPH::Factory)));
    ::new(factory) JPH::Factory();
    JPH::Factory::sInstance = factory;
    JPH::RegisterTypes();

    shape_pool = alloc_t<ShapePool>();
    ::new(shape_pool) ShapePool();
}

void deinit() {
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

ShapeHandle create_sphere_shape(float radius, float density) {
    auto settings = JPH::SphereShapeSettings();
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->insert(shape);
}

ShapeHandle create_box_shape(const float half_extent[3], float density) {
    auto settings = JPH::BoxShapeSettings();
    settings.mHalfExtent = load_vec3(half_extent);
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->insert(shape);

}

ShapeHandle create_cylinder_shape(float half_height, float radius, float density) {
    auto settings = JPH::CylinderShapeSettings();
    settings.mHalfHeight = half_height;
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->insert(shape);

}

ShapeHandle create_capsule_shape(float half_height, float radius, float density) {
    auto settings = JPH::CapsuleShapeSettings();
    settings.mHalfHeightOfCylinder = half_height;
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->insert(shape);

}

ShapeHandle
create_convex_hull_shape(const float positions[][3], size_t position_count, float density) {
    JPH::Array<JPH::Vec3> point_list(position_count);
    for (size_t i = 0; i < position_count; i++) {
        point_list[i] = load_vec3(positions[i]);
    }
    auto settings = JPH::ConvexHullShapeSettings();
    settings.mPoints = point_list;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->insert(shape);
}

ShapeHandle
create_mesh_shape(const float positions[][3], size_t position_count, const uint32_t *indices, size_t indices_count) {
    JPH::VertexList vertex_list;
    for (size_t i = 0; i < position_count; i++) {
        vertex_list.push_back(load_float3(positions[i]));
    }

    JPH::IndexedTriangleList triangle_list;

    if (indices_count == 0) {
        for (int i = 0; i < position_count; i += 3) {
            triangle_list.push_back(JPH::IndexedTriangle(i + 0, i + 1, i + 2, 0));
        }
    } else {
        const size_t triangle_count = indices_count / 3;
        for (int i = 0; i < triangle_count; i++) {
            const size_t offset = i * 3;
            triangle_list.push_back(JPH::IndexedTriangle(
                    indices[offset + 0], indices[offset + 1], indices[offset + 2], 0));
        }
    }

    auto shape = JPH::MeshShapeSettings(vertex_list, triangle_list).Create().Get();
    return shape_pool->insert(shape);

}

ShapeHandle create_mut_compound_shape() {
    auto shape = JPH::MutableCompoundShapeSettings().Create().Get();
    return shape_pool->insert(shape);
}

void destroy_shape(ShapeHandle handle) {
    shape_pool->remove(handle);
}

ChildShapeHandle
add_child_shape(ShapeHandle compound_shape_handle, const Transform *child_transform, ShapeHandle child_shape_handle,
                uint32_t user_data) {
    auto position = load_vec3(child_transform->position);
    auto rotation = load_quat(child_transform->rotation);
    auto child_shape_ref = shape_pool->get(child_shape_handle);
    JPH::MutableCompoundShape *compound_shape = dynamic_cast<JPH::MutableCompoundShape *>(shape_pool->get(
            compound_shape_handle).GetPtr());
    return compound_shape->AddShape(position, rotation, child_shape_ref, user_data);
}

void remove_child_shape(ShapeHandle compound_shape_handle, ChildShapeHandle child_shape_handle) {
    JPH::MutableCompoundShape *compound_shape = dynamic_cast<JPH::MutableCompoundShape *>(shape_pool->get(
            compound_shape_handle).GetPtr());
    compound_shape->RemoveShape(child_shape_handle);
}

void
modify_child_shape(ShapeHandle compound_shape_handle, ChildShapeHandle child_shape_handle,
                   const Transform *child_transform) {
    auto position = load_vec3(child_transform->position);
    auto rotation = load_quat(child_transform->rotation);
    JPH::MutableCompoundShape *compound_shape = dynamic_cast<JPH::MutableCompoundShape *>(shape_pool->get(
            compound_shape_handle).GetPtr());
    compound_shape->ModifyShape(child_shape_handle, position, rotation);
}

void recalculate_center_of_mass(ShapeHandle compound_shape_handle) {
    JPH::MutableCompoundShape *compound_shape = dynamic_cast<JPH::MutableCompoundShape *>(shape_pool->get(
            compound_shape_handle).GetPtr());
    compound_shape->AdjustCenterOfMass();
}


PhysicsWorld *create_physics_world(const PhysicsWorldSettings *settings) {
    auto physics_world = alloc_t<PhysicsWorld>();
    ::new(physics_world) PhysicsWorld(settings);
    return (PhysicsWorld *) physics_world;
}

void destroy_physics_world(PhysicsWorld *ptr) {
    auto physics_world = (PhysicsWorld *) ptr;
    physics_world->~PhysicsWorld();
    free_t(physics_world);
}

void update_physics_world(PhysicsWorld *ptr, float delta_time, int collision_steps) {
    auto physics_world = (PhysicsWorld *) ptr;
    physics_world->update(delta_time, collision_steps);
}

BodyHandle create_body(PhysicsWorld *ptr, const BodySettings *body_settings) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto shape_ref = shape_pool->get(body_settings->shape);
    auto position = load_vec3(body_settings->position);
    auto rotation = load_quat(body_settings->rotation);
    auto linear_velocity = load_vec3(body_settings->linear_velocity);
    auto angular_velocity = load_vec3(body_settings->angular_velocity);
    auto settings = JPH::BodyCreationSettings();
    settings.SetShape(shape_ref);
    settings.mPosition = position;
    settings.mRotation = rotation;
    settings.mLinearVelocity = linear_velocity;
    settings.mAngularVelocity = angular_velocity;
    settings.mUserData = body_settings->user_data;
    settings.mObjectLayer = body_settings->object_layer;

    switch (body_settings->motion_type) {
        case 0:
            settings.mMotionType = JPH::EMotionType::Static;
            break;
        case 1:
            settings.mMotionType = JPH::EMotionType::Kinematic;
            break;
        case 2:
            settings.mMotionType = JPH::EMotionType::Dynamic;
            break;
    }

    settings.mIsSensor = body_settings->is_sensor;
    settings.mAllowSleeping = body_settings->allow_sleep;
    settings.mFriction = body_settings->friction;
    settings.mGravityFactor = body_settings->gravity_factor;
    settings.mLinearDamping = body_settings->linear_damping;
    settings.mAngularDamping = body_settings->angular_damping;

    JPH::BodyInterface &body_interface =
            physics_world->physics_system->GetBodyInterface();
    JPH::BodyID body_id =
            body_interface.CreateAndAddBody(settings, JPH::EActivation::Activate);

    if (body_settings->is_sensor) {
        physics_world->volume_bodies.emplace(body_id, VolumeBody());
    }

    return body_id.GetIndexAndSequenceNumber();
}

void destroy_body(PhysicsWorld *ptr, BodyHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface =
            physics_world->physics_system->GetBodyInterface();

    physics_world->volume_bodies.erase(body_id);

    body_interface.RemoveBody(body_id);
    body_interface.DestroyBody(body_id);
}

Transform get_body_transform(PhysicsWorld *ptr, BodyHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface =
            physics_world->physics_system->GetBodyInterface();
    JPH::RVec3 position{};
    JPH::Quat rotation{};
    body_interface.GetPositionAndRotation(body_id, position, rotation);
    return Transform{
            {position.GetX(), position.GetY(), position.GetZ()},
            {rotation.GetX(), rotation.GetY(), rotation.GetZ(), rotation.GetW()}};
}

void set_body_transform(PhysicsWorld *ptr, BodyHandle handle, const Transform *transform) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface =
            physics_world->physics_system->GetBodyInterface();

    auto position = load_rvec3(transform->position);
    auto rotation = load_quat(transform->rotation);
    body_interface.SetPositionAndRotationWhenChanged(body_id, position, rotation, JPH::EActivation::Activate);
}

void get_body_linear_velocity(PhysicsWorld *ptr, BodyHandle handle, float *velocity_ptr) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface =
            physics_world->physics_system->GetBodyInterface();
    auto velocity = body_interface.GetLinearVelocity(body_id);
    velocity_ptr[0] = velocity.GetX();
    velocity_ptr[1] = velocity.GetY();
    velocity_ptr[2] = velocity.GetZ();
}

void set_body_linear_velocity(PhysicsWorld *ptr, BodyHandle handle, const float velocity[3]) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface =
            physics_world->physics_system->GetBodyInterface();
    auto linear_velocity = load_vec3(velocity);
    body_interface.SetLinearVelocity(body_id, linear_velocity);
}

void get_body_angular_velocity(PhysicsWorld *ptr, BodyHandle handle, float *velocity_ptr) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface =
            physics_world->physics_system->GetBodyInterface();
    auto velocity = body_interface.GetAngularVelocity(body_id);
    velocity_ptr[0] = velocity.GetX();
    velocity_ptr[1] = velocity.GetY();
    velocity_ptr[2] = velocity.GetZ();
}

void set_body_angular_velocity(PhysicsWorld *ptr, BodyHandle handle, const float velocity[3]) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface =
            physics_world->physics_system->GetBodyInterface();
    auto angular_velocity = load_vec3(velocity);
    body_interface.SetAngularVelocity(body_id, angular_velocity);
}


BodyHandleList get_body_contact_list(PhysicsWorld *ptr, BodyHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    if (physics_world->volume_bodies.find(body_id) !=
        physics_world->volume_bodies.end()) {
        auto contact_list_ref = &physics_world->volume_bodies[body_id].contact_list;
        return BodyHandleList{
                reinterpret_cast<BodyHandle *>(contact_list_ref->get_ptr()),
                contact_list_ref->size()};

    } else {
        return BodyHandleList{nullptr, 0};
    }
}

void set_body_gravity_mode_radial(PhysicsWorld *ptr, BodyHandle handle, float gravity_strength) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    if (physics_world->volume_bodies.find(body_id) !=
        physics_world->volume_bodies.end()) {
        physics_world->volume_bodies[body_id].gravity = GravityMode::with_radial(RadialGravity{
                JPH::RVec3::sReplicate(0.0), gravity_strength
        });
    }
}

void set_body_gravity_mode_vector(PhysicsWorld *ptr, BodyHandle handle, const float gravity[3]) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    if (physics_world->volume_bodies.find(body_id) !=
        physics_world->volume_bodies.end()) {
        physics_world->volume_bodies[body_id].gravity = GravityMode::with_vector(VectorGravity{
                load_rvec3(gravity)
        });
    }
}

void clear_body_gravity_mode(PhysicsWorld *ptr, BodyHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto body_id = JPH::BodyID(handle);
    if (physics_world->volume_bodies.find(body_id) !=
        physics_world->volume_bodies.end()) {
        physics_world->volume_bodies[body_id].gravity.reset();
    }
}

CharacterHandle add_character(PhysicsWorld *ptr, const CharacterSettings *character_settings) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto shape_ref = shape_pool->get(character_settings->shape);
    auto inner_shape_ref = shape_pool->get(character_settings->inner_body_shape);
    auto position = load_vec3(character_settings->position);
    auto rotation = load_quat(character_settings->rotation);
    return physics_world->add_character(shape_ref, position, rotation, character_settings->user_data, inner_shape_ref,
                                        character_settings->inner_body_layer);
}

void destroy_character(PhysicsWorld *ptr, CharacterHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    physics_world->remove_character(handle);
}

void set_character_position(PhysicsWorld *ptr, CharacterHandle handle, const float position[3]) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];
    auto r_position = load_rvec3(position);
    character->character->SetPosition(r_position);
}

void set_character_rotation(PhysicsWorld *ptr, CharacterHandle handle, const float rotation[4]) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];
    auto rotation_quat = load_quat(rotation);
    character->character->SetRotation(rotation_quat);
    character->character->SetUp(rotation_quat.RotateAxisY());
}

Transform get_character_transform(PhysicsWorld *ptr, CharacterHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];

    Transform transform;
    character->character->GetPosition().StoreFloat3(
            reinterpret_cast<JPH::Real3 *>(transform.position));
    character->character->GetRotation().GetXYZW().StoreFloat4(
            reinterpret_cast<JPH::Float4 *>(transform.rotation));
    return transform;
}

void get_character_linear_velocity(PhysicsWorld *ptr, CharacterHandle handle, float *velocity_ptr) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];
    auto velocity = character->character->GetLinearVelocity();
    velocity_ptr[0] = velocity.GetX();
    velocity_ptr[1] = velocity.GetY();
    velocity_ptr[2] = velocity.GetZ();
}

void set_character_linear_velocity(PhysicsWorld *ptr, CharacterHandle handle, const float velocity[3]) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];
    character->character->SetLinearVelocity(load_vec3(velocity));
}

void get_character_ground_velocity(PhysicsWorld *ptr, CharacterHandle handle, float *velocity_ptr) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];

    if (character->character->GetGroundState() ==
        JPH::CharacterBase::EGroundState::OnGround) {
        auto velocity = character->character->GetGroundVelocity();
        velocity_ptr[0] = velocity.GetX();
        velocity_ptr[1] = velocity.GetY();
        velocity_ptr[2] = velocity.GetZ();
    } else {
        velocity_ptr[0] = 0.0f;
        velocity_ptr[1] = 0.0f;
        velocity_ptr[2] = 0.0f;
    }
}

GroundState get_character_ground_state(PhysicsWorld *ptr, CharacterHandle handle) {
    auto physics_world = (PhysicsWorld *) ptr;
    auto character = physics_world->characters[handle];

    GroundState ground_state;
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

void convert_ray_hit(RayCastHit *hit_result, JPH::RayCast &ray, JPH::RayCastResult &hit,
                     const JPH::BodyLockInterfaceLocking &body_lock_interface) {
    auto ray_distance = ray.mDirection * hit.mFraction;
    auto ws_position = ray.mOrigin + ray_distance;

    hit_result->body = hit.mBodyID.GetIndexAndSequenceNumber();
    hit_result->shape_index = 0;//hit.mSubShapeID2.GetValue(); //TODO: figure this out once sub-shapes are supported
    hit_result->distance = ray_distance.Length();
    hit_result->ws_position[0] = ws_position.GetX();
    hit_result->ws_position[1] = ws_position.GetY();
    hit_result->ws_position[2] = ws_position.GetZ();

    {
        JPH::BodyLockRead lock(body_lock_interface, hit.mBodyID);
        if (lock.Succeeded()) {
            const JPH::Body &body = lock.GetBody();
            auto ws_normal = body.GetWorldSpaceSurfaceNormal(hit.mSubShapeID2, ws_position);
            hit_result->ws_normal[0] = ws_normal.GetX();
            hit_result->ws_normal[1] = ws_normal.GetY();
            hit_result->ws_normal[2] = ws_normal.GetZ();
            hit_result->body_user_data = body.GetUserData();
            hit_result->shape_user_data = body.GetShape()->GetSubShapeUserData(hit.mSubShapeID2);
        }
    }
}


bool
ray_cast_closest(PhysicsWorld *ptr, ObjectLayer object_layer_pattern,
                 const float origin[3], const float direction[3],
                 RayCastHit *hit_result) {
    auto physics_world = (PhysicsWorld *) ptr;
    JPH::RayCast ray(load_vec3(origin), load_vec3(direction));
    JPH::RayCastResult hit;

    JPH::BroadPhaseLayerFilter broad_phase_filter{};
    AnyMatchObjectLayerFilter layer_filter(object_layer_pattern);
    JPH::BodyFilter body_filter{};

    bool has_hit = physics_world->physics_system->GetNarrowPhaseQuery().CastRay(JPH::RRayCast(ray), hit,
                                                                                broad_phase_filter, layer_filter,
                                                                                body_filter);

    if (has_hit) {
        convert_ray_hit(hit_result, ray, hit, physics_world->physics_system->GetBodyLockInterface());
    }
    return has_hit;
}

bool
ray_cast_closest_ignore(PhysicsWorld *ptr, ObjectLayer object_layer_pattern, BodyHandle ignore_body,
                        const float origin[3], const float direction[3],
                        RayCastHit *hit_result) {
    auto physics_world = (PhysicsWorld *) ptr;
    JPH::RayCast ray(load_vec3(origin), load_vec3(direction));
    JPH::RayCastResult hit;

    JPH::BroadPhaseLayerFilter broad_phase_filter{};
    AnyMatchObjectLayerFilter layer_filter(object_layer_pattern);
    JPH::IgnoreSingleBodyFilter body_filter{JPH::BodyID(ignore_body)};

    bool has_hit = physics_world->physics_system->GetNarrowPhaseQuery().CastRay(JPH::RRayCast(ray), hit,
                                                                                broad_phase_filter, layer_filter,
                                                                                body_filter);

    if (has_hit) {
        convert_ray_hit(hit_result, ray, hit, physics_world->physics_system->GetBodyLockInterface());
    }
    return has_hit;
}

bool
ray_cast_closest_ignore_character(PhysicsWorld *ptr, ObjectLayer object_layer_pattern, CharacterHandle ignore_character,
                                  const float origin[3], const float direction[3],
                                  RayCastHit *hit_result) {
    auto physics_world = (PhysicsWorld *) ptr;
    JPH::RayCast ray(load_vec3(origin), load_vec3(direction));
    JPH::RayCastResult hit;

    auto character = physics_world->characters[ignore_character];

    JPH::BroadPhaseLayerFilter broad_phase_filter{};
    AnyMatchObjectLayerFilter layer_filter(object_layer_pattern);
    JPH::IgnoreSingleBodyFilter body_filter{character->character->GetInnerBodyID()};

    bool has_hit = physics_world->physics_system->GetNarrowPhaseQuery().CastRay(JPH::RRayCast(ray), hit,
                                                                                broad_phase_filter, layer_filter,
                                                                                body_filter);

    if (has_hit) {
        convert_ray_hit(hit_result, ray, hit, physics_world->physics_system->GetBodyLockInterface());
    }
    return has_hit;
}


void shape_cast(PhysicsWorld *ptr, ObjectLayer object_layer_pattern, ShapeHandle shape, const Transform *transform,
                ShapeCastCallback callback, void *callback_data) {
    auto physics_world = (PhysicsWorld *) ptr;
    const auto &shape_ref = shape_pool->get(shape);
    auto position = load_rvec3(transform->position);
    auto rotation = load_quat(transform->rotation);
    auto center_of_mass_transform = JPH::RMat44::sRotationTranslation(rotation, position);

    JPH::CollideShapeSettings settings = JPH::CollideShapeSettings();
    ShapeCastCallbackCollisionCollector collector(callback, callback_data,
                                                  physics_world->physics_system->GetBodyInterface());

    physics_world->physics_system->GetNarrowPhaseQuery().CollideShape(shape_ref, JPH::Vec3::sReplicate(1.0f),
                                                                      center_of_mass_transform, settings, position,
                                                                      collector, {}, AnyMatchObjectLayerFilter(
                    object_layer_pattern), {}, {});
}
