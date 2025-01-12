#include "saturn_jolt.h"

#include <cstdio>
#include <iostream>
#include <thread>

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Physics/Collision/Shape/MutableCompoundShape.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/RayCast.h>

#include "memory.hpp"
#include "shape_pool.hpp"

#include "world.hpp"
#include "body.hpp"
#include "Jolt/Physics/Collision/Shape/SphereShape.h"
#include "Jolt/Physics/Collision/Shape/BoxShape.h"
#include "Jolt/Physics/Collision/Shape/CylinderShape.h"
#include "Jolt/Physics/Collision/Shape/CapsuleShape.h"
#include "Jolt/Physics/Collision/Shape/ConvexHullShape.h"
#include "Jolt/Physics/Collision/Shape/MeshShape.h"

ShapePool *shape_pool = nullptr;
std::mutex shape_pool_mutex;

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
    shape_pool_mutex.lock();
    shape_pool->~ShapePool();
    free_t(shape_pool);
    shape_pool_mutex.unlock();

    JPH::UnregisterTypes();
    JPH::Factory::sInstance->~Factory();
    JPH::Free((void *) JPH::Factory::sInstance);
    JPH::Factory::sInstance = nullptr;

    JPH::Allocate = nullptr;
    JPH::Free = nullptr;
    JPH::AlignedAllocate = nullptr;
    JPH::AlignedFree = nullptr;
}

Shape shapeCreateSphere(float radius, float density, UserData user_data) {
    auto settings = JPH::SphereShapeSettings();
    settings.mRadius = radius;
    settings.mDensity = density;
    settings.mUserData = user_data;
    auto shape = settings.Create().Get();
    shape_pool_mutex.lock();
    auto shape_handle = shape_pool->insert(shape);
    shape_pool_mutex.unlock();
    return shape_handle;

}

Shape shapeCreateBox(const Vec3 half_extent, float density, UserData user_data) {
    auto settings = JPH::BoxShapeSettings();
    settings.mHalfExtent = load_vec3(half_extent);
    settings.mDensity = density;
    settings.mUserData = user_data;

    auto shape = settings.Create().Get();
    shape_pool_mutex.lock();
    shape_pool_mutex.lock();
    auto shape_handle = shape_pool->insert(shape);
    shape_pool_mutex.unlock();
    return shape_handle;

}

Shape shapeCreateCylinder(float half_height, float radius, float density, UserData user_data) {
    auto settings = JPH::CylinderShapeSettings();
    settings.mHalfHeight = half_height;
    settings.mRadius = radius;
    settings.mDensity = density;
    settings.mUserData = user_data;

    auto shape = settings.Create().Get();
    shape_pool_mutex.lock();
    auto shape_handle = shape_pool->insert(shape);
    shape_pool_mutex.unlock();
    return shape_handle;

}

Shape shapeCreateCapsule(float half_height, float radius, float density, UserData user_data) {
    auto settings = JPH::CapsuleShapeSettings();
    settings.mHalfHeightOfCylinder = half_height;
    settings.mRadius = radius;
    settings.mDensity = density;
    settings.mUserData = user_data;

    auto shape = settings.Create().Get();
    shape_pool_mutex.lock();
    auto shape_handle = shape_pool->insert(shape);
    shape_pool_mutex.unlock();
    return shape_handle;

}

Shape shapeCreateConvexHull(const Vec3 positions[], size_t position_count, float density, UserData user_data) {
    JPH::Array<JPH::Vec3> point_list(position_count);
    for (size_t i = 0; i < position_count; i++) {
        point_list[i] = load_vec3(positions[i]);
    }
    auto settings = JPH::ConvexHullShapeSettings();
    settings.mPoints = point_list;
    settings.mDensity = density;
    settings.mUserData = user_data;

    auto shape = settings.Create().Get();
    shape_pool_mutex.lock();
    auto shape_handle = shape_pool->insert(shape);
    shape_pool_mutex.unlock();
    return shape_handle;

}

Shape shapeCreateMesh(const Vec3 positions[], size_t position_count, const uint32_t *indices, size_t indices_count, UserData user_data) {
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

    auto settings = JPH::MeshShapeSettings(vertex_list, triangle_list);
    settings.mUserData = user_data;
    auto shape = settings.Create().Get();
    shape_pool_mutex.lock();
    auto shape_handle = shape_pool->insert(shape);
    shape_pool_mutex.unlock();
    return shape_handle;

}

void shapeDestroy(Shape shape) {
    shape_pool_mutex.lock();
    shape_pool->remove(shape);
    shape_pool_mutex.unlock();
}

World *worldCreate(const WorldSettings *settings) {
    auto world_ptr = alloc_t<World>();
    ::new(world_ptr) World(settings);
    return world_ptr;
}

void worldDestroy(World *world_ptr) {
    world_ptr->~World();
    free_t(world_ptr);
}

void worldUpdate(World *world_ptr, float delta_time, int collision_steps) {
    world_ptr->update(delta_time, collision_steps);
}

void worldAddBody(World *world_ptr, Body *body_ptr) {
    world_ptr->addBody(body_ptr);
}

void worldRemoveBody(World *world_ptr, Body *body_ptr) {
    world_ptr->removeBody(body_ptr);
}

// Body functions
Body *bodyCreate(const BodySettings *settings) {
    auto body_ptr = alloc_t<Body>();
    ::new(body_ptr) Body(settings);
    return body_ptr;
}

void bodyDestroy(Body *body_ptr) {
    body_ptr->~Body();
    free_t(body_ptr);
}

World *bodyGetWorld(Body *body_ptr) {
    return body_ptr->getWorld();
}

Transform bodyGetTransform(Body *body_ptr) {
    auto position = body_ptr->getPosition();
    auto rotation = body_ptr->getRotation();
    return Transform{
            {position.GetX(), position.GetY(), position.GetZ()},
            {rotation.GetX(), rotation.GetY(), rotation.GetZ(), rotation.GetW()}};
}

void bodySetTransform(Body *body_ptr, const Transform *c_transform) {
    body_ptr->setTransform(load_rvec3(c_transform->position), load_quat(c_transform->rotation));
}

Velocity bodyGetVelocity(Body *body_ptr) {
    auto linear = body_ptr->getLinearVelocity();
    auto angular = body_ptr->getAngularVelocity();
    return Velocity{
            {linear.GetX(),  linear.GetY(),  linear.GetZ()},
            {angular.GetX(), angular.GetY(), angular.GetZ()},

    };
}

void bodySetVelocity(Body *body_ptr, const Velocity *c_velocity) {
    body_ptr->setVelocity(load_vec3(c_velocity->linear), load_vec3(c_velocity->angular));
}