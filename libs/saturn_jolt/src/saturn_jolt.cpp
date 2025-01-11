#include "saturn_jolt.h"

#include <cstdio>
#include <iostream>
#include <thread>

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/MutableCompoundShape.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/RayCast.h>

#include "memory.hpp"
#include "shape_pool.hpp"

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

