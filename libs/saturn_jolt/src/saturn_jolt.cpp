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