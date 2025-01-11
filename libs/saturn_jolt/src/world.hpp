#pragma once

#include <optional>
#include <variant>

#include <Jolt/Jolt.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Physics/PhysicsSystem.h>

#include "layer_filters.hpp"
#include "memory.hpp"
#include "saturn_jolt.h"

class World {
    World(const WorldSettings *settings);

    ~World();

    void update(float delta_time, int collision_steps);

public:
    BroadPhaseLayerInterfaceImpl *broad_phase_layer_interface;
    ObjectVsBroadPhaseLayerFilterImpl *object_vs_broadphase_layer_filter;
    AnyMatchObjectLayerPairFilter *object_vs_object_layer_filter;
    JPH::PhysicsSystem *physics_system;

    //TODO: replace these with global versions?
    JPH::TempAllocatorImplWithMallocFallback temp_allocator;
    JPH::JobSystemSingleThreaded job_system;
};
