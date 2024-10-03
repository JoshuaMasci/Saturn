#pragma once

#include <optional>
#include <variant>

#include <Jolt/Jolt.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Physics/PhysicsSystem.h>

#include "layer_filters.hpp"
#include "memory.hpp"
#include "saturn_jolt.h"

class MyContactListener;

class GravityStepListener;

class ContactList {
public:
    void add(JPH::BodyID);

    void remove(JPH::BodyID);

    size_t size();

    JPH::BodyID *get_ptr() { return this->ids.data(); }

    JoltVector<JPH::BodyID> &get_id_list() { return this->ids; }

private:
    // TODO: include sub-shape ids as part of this at some point
    JoltVector<JPH::BodyID> ids;
    JoltVector<int32_t> contact_count;
};

class Character;

struct RadialGravity {
    JPH::Vec3 offset;
    float strength;
};

struct VectorGravity {
    JPH::Vec3 gravity;
};


struct GravityMode {
    std::variant<RadialGravity, VectorGravity> mode;

    JPH::Vec3 get_velocity(JPH::RVec3 volume_position, JPH::Quat volume_rotation, JPH::RVec3 body_position) {
        if (std::holds_alternative<RadialGravity>(this->mode)) {
            RadialGravity gravity = std::get<RadialGravity>(this->mode);
            JPH::RVec3 difference = (volume_position + (volume_rotation * gravity.offset)) - body_position;
            JPH::Real distance2 = difference.LengthSq();
            return difference.Normalized() * (gravity.strength / distance2);
        } else if (std::holds_alternative<VectorGravity>(this->mode)) {
            VectorGravity gravity = std::get<VectorGravity>(this->mode);
            return volume_rotation * gravity.gravity;
        } else {
            return JPH::Vec3::sReplicate(0.0);
        }
    }

    JPH::RVec3 get_up(JPH::RVec3 volume_position, JPH::Quat volume_rotation, JPH::RVec3 body_position) {
        if (std::holds_alternative<RadialGravity>(this->mode)) {
            RadialGravity gravity = std::get<RadialGravity>(this->mode);
            return (body_position - (volume_position + (volume_rotation * gravity.offset))).Normalized();
        } else if (std::holds_alternative<VectorGravity>(this->mode)) {
            VectorGravity gravity = std::get<VectorGravity>(this->mode);
            return (volume_rotation * (gravity.gravity * -1.0)).Normalized();
        } else {
            return {0.0, 1.0, 0.0};
        }
    }

    static GravityMode with_radial(RadialGravity radial) {
        return GravityMode{
                radial
        };
    }

    static GravityMode with_vector(VectorGravity radial) {
        return GravityMode{
                radial
        };
    }
};


struct VolumeBody {
    ContactList contact_list;
    std::optional<GravityMode> gravity;
};

class PhysicsWorld {
public:
    PhysicsWorld(const PhysicsWorldSettings *settings);

    ~PhysicsWorld();

    void update(float delta_time, int collision_steps);

    CharacterHandle add_character(JPH::RefConst<JPH::Shape> shape, JPH::RVec3 position, JPH::Quat rotation);

    void remove_character(CharacterHandle handle);

public:
    BroadPhaseLayerInterfaceImpl *broad_phase_layer_interface;
    ObjectVsBroadPhaseLayerFilterImpl *object_vs_broadphase_layer_filter;
    AnyMatchObjectLayerPairFilter *object_vs_object_layer_filter;
    JPH::PhysicsSystem *physics_system;
    MyContactListener *contact_listener;
    GravityStepListener *gravity_step_listener;

    CharacterHandle next_character_index = 0;
    JPH::UnorderedMap<CharacterHandle, Character *> characters;

    JPH::UnorderedMap<JPH::BodyID, VolumeBody> volume_bodies;

    JPH::TempAllocatorImpl temp_allocator;
    JPH::JobSystemSingleThreaded job_system;
};
