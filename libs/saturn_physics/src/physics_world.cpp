#include "physics_world.hpp"

#include "contact_listener.hpp"
#include "gravity_step_listener.hpp"

#include "character.hpp"

int32_t vec_find(JoltVector<JPH::BodyID> &vec, JPH::BodyID id) {
    for (int32_t i = 0; i < vec.size(); i++) {
        if (vec[i] == id) {
            return i;
        }
    }
    return -1;
}

void ContactList::add(JPH::BodyID id) {
    auto current_index = vec_find(this->ids, id);
    if (current_index != -1) {
        this->contact_count[current_index] += 1;
    } else {
        this->ids.emplace_back(id);
        this->contact_count.emplace_back(1);
    }
    //printf("Add: %zu\n", this->size());
}

void ContactList::remove(JPH::BodyID id) {
    auto current_index = vec_find(this->ids, id);
    if (current_index != -1) {
        this->contact_count[current_index] -= 1;
        if (this->contact_count[current_index] <= 0) {
            auto last_index = this->ids.size() - 1;
            if (current_index != last_index) {
                JPH::swap(this->ids[current_index], this->ids[last_index]);
                JPH::swap(this->contact_count[current_index], this->contact_count[last_index]);
            }
            this->ids.pop_back();
            this->contact_count.pop_back();
        }
    }
    //printf("Remove: %zu\n", this->size());
}

size_t ContactList::size() {
    return this->ids.size();
}

PhysicsWorld::PhysicsWorld(const PhysicsWorldSettings *settings)
        : temp_allocator(settings->temp_allocation_size), job_system(1024) {
    this->broad_phase_layer_interface = alloc_t<BPLayerInterfaceImpl>();
    ::new(this->broad_phase_layer_interface) BPLayerInterfaceImpl();

    this->object_vs_broadphase_layer_filter = alloc_t<ObjectVsBroadPhaseLayerFilterImpl>();
    ::new(this->object_vs_broadphase_layer_filter) ObjectVsBroadPhaseLayerFilterImpl();

    this->object_vs_object_layer_filter = alloc_t<ObjectLayerPairFilterImpl>();
    ::new(this->object_vs_object_layer_filter) ObjectLayerPairFilterImpl();

    this->physics_system = alloc_t<JPH::PhysicsSystem>();
    ::new(this->physics_system) JPH::PhysicsSystem();
    this->physics_system->Init(settings->max_bodies, settings->num_body_mutexes, settings->max_body_pairs,
                               settings->max_contact_constraints, *this->broad_phase_layer_interface,
                               *this->object_vs_broadphase_layer_filter, *this->object_vs_object_layer_filter);

    this->contact_listener = alloc_t<MyContactListener>();
    ::new(this->contact_listener) MyContactListener(this);
    this->physics_system->SetContactListener(this->contact_listener);

    this->physics_system->SetGravity(JPH::Vec3(0.0, 0.0, 0.0));
    this->gravity_step_listener = alloc_t<GravityStepListener>();
    ::new(this->gravity_step_listener) GravityStepListener(this);
    this->physics_system->AddStepListener(this->gravity_step_listener);
}

PhysicsWorld::~PhysicsWorld() {
    for (auto pair: this->characters) {
        pair.second->~Character();
        free_t(pair.second);
    }

    this->physics_system->RemoveStepListener(this->gravity_step_listener);
    this->gravity_step_listener->~GravityStepListener();
    free_t(this->gravity_step_listener);

    this->physics_system->SetContactListener(nullptr);
    this->contact_listener->~MyContactListener();
    free_t(this->contact_listener);

    this->physics_system->~PhysicsSystem();
    free_t(this->physics_system);

    this->broad_phase_layer_interface->~BPLayerInterfaceImpl();
    free_t(this->broad_phase_layer_interface);

    this->object_vs_broadphase_layer_filter->~ObjectVsBroadPhaseLayerFilterImpl();
    free_t(this->object_vs_broadphase_layer_filter);

    this->object_vs_object_layer_filter->~ObjectLayerPairFilterImpl();
    free_t(this->object_vs_object_layer_filter);
}


void PhysicsWorld::update(float delta_time, int collision_steps) {
    this->physics_system->Update(delta_time, collision_steps, &this->temp_allocator,
                                 &this->job_system);

    for (auto pair: this->characters) {
        pair.second->update(this, delta_time);
    }
}

CharacterHandle
PhysicsWorld::add_character(JPH::RefConst<JPH::Shape> shape, const JPH::RVec3 position, const JPH::Quat rotation) {
    auto new_character = alloc_t<Character>();
    ::new(new_character) Character(this, shape, position, rotation);
    auto character_handle = this->next_character_index;
    this->next_character_index++;
    this->characters.emplace(character_handle, new_character);
    return character_handle;
}

void PhysicsWorld::remove_character(CharacterHandle handle) {
    auto character = this->characters[handle];
    character->~Character();
    free_t(character);

    this->characters.erase(handle);
}
