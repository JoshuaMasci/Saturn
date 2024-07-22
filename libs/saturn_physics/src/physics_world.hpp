#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>

#include "layer_filters.hpp"
#include "saturn_jolt.h"
#include "memory.hpp"

class MyContactListener;

class PhysicsWorld
{
public:
    PhysicsWorld(const SPH_PhysicsWorldSettings *settings);
    ~PhysicsWorld();

public:
    BPLayerInterfaceImpl *broad_phase_layer_interface;
    ObjectVsBroadPhaseLayerFilterImpl *object_vs_broadphase_layer_filter;
    ObjectLayerPairFilterImpl *object_vs_object_layer_filter;
    JPH::PhysicsSystem *physics_system;
    MyContactListener *contact_listener;

    // TODO: include sub-shape ids as part of this at some point
    JPH::UnorderedMap<JPH::BodyID, JPH::UnorderedSet<JPH::BodyID>> volume_list;

    JPH::TempAllocatorImpl temp_allocator;
    JPH::JobSystemSingleThreaded job_system;
};