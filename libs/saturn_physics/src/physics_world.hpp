#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>

#include "layer_filters.hpp"
#include "saturn_jolt.h"
#include "memory.hpp"

class MyContactListener;

class GravityStepListener;

class ContactList {
public:
    void add(JPH::BodyID);

    void remove(JPH::BodyID);

    size_t size();

    JPH::BodyID *get_ptr() { return this->ids.data(); }

    JoltVector<JPH::BodyID> &get_id_list() {
        return this->ids;
    }

private:
    JoltVector<JPH::BodyID> ids;
    JoltVector<int32_t> contact_count;
};

class PhysicsWorld {
public:
    PhysicsWorld(const SPH_PhysicsWorldSettings *settings);

    ~PhysicsWorld();

public:
    BPLayerInterfaceImpl *broad_phase_layer_interface;
    ObjectVsBroadPhaseLayerFilterImpl *object_vs_broadphase_layer_filter;
    ObjectLayerPairFilterImpl *object_vs_object_layer_filter;
    JPH::PhysicsSystem *physics_system;
    MyContactListener *contact_listener;
    GravityStepListener *gravity_step_listener;

    // TODO: include sub-shape ids as part of this at some point
    JPH::UnorderedMap<JPH::BodyID, ContactList> contact_lists;

    JPH::TempAllocatorImpl temp_allocator;
    JPH::JobSystemSingleThreaded job_system;
};