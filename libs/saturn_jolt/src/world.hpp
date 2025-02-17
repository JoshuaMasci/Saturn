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
public:
    explicit World(const WorldSettings *settings);

    ~World();

    void update(float delta_time, int collision_steps);

    void addBody(Body *body);

    void removeBody(Body *body);

    bool castRayCloset(ObjectLayer object_layer_pattern, JPH::RVec3 origin, JPH::RVec3 direction, RayCastHit *hit_result) const;

    bool castRayClosetIgnoreBody(ObjectLayer object_layer_pattern, JPH::BodyID ignore_body, JPH::RVec3 origin, JPH::RVec3 direction, RayCastHit *hit_result) const;

	void castShape(ObjectLayer object_layer_pattern, JPH::RVec3 position, JPH::Quat rotation, const JPH::Ref<JPH::Shape>& shape_ref, ShapeCastCallback callback, void *callback_data) const;

    JPH::PhysicsSystem *physics_system;

private:
    BroadPhaseLayerInterfaceImpl *broad_phase_layer_interface;
    ObjectVsBroadPhaseLayerFilterImpl *object_vs_broadphase_layer_filter;
    AnyMatchObjectLayerPairFilter *object_vs_object_layer_filter;

    //TODO: replace these with global versions?
    JPH::TempAllocatorImplWithMallocFallback temp_allocator;
    JPH::JobSystemSingleThreaded job_system;
};
