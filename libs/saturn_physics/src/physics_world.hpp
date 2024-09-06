#pragma once

#include <Jolt/Jolt.h>
#include <optional>

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

struct VolumeBody {
	ContactList contact_list;
	std::optional<float> gravity_strength;
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
