#include "physics_world.hpp"

#include "contact_listener.hpp"

PhysicsWorld::PhysicsWorld(const SPH_PhysicsWorldSettings *settings)
        : temp_allocator(settings->temp_allocation_size), job_system(1024)
{
    this->broad_phase_layer_interface = alloc_t<BPLayerInterfaceImpl>();
    ::new (this->broad_phase_layer_interface) BPLayerInterfaceImpl();

    this->object_vs_broadphase_layer_filter = alloc_t<ObjectVsBroadPhaseLayerFilterImpl>();
    ::new (this->object_vs_broadphase_layer_filter) ObjectVsBroadPhaseLayerFilterImpl();

    this->object_vs_object_layer_filter = alloc_t<ObjectLayerPairFilterImpl>();
    ::new (this->object_vs_object_layer_filter) ObjectLayerPairFilterImpl();

    this->physics_system = alloc_t<JPH::PhysicsSystem>();
    ::new (this->physics_system) JPH::PhysicsSystem();
    this->physics_system->Init(settings->max_bodies, settings->num_body_mutexes, settings->max_body_pairs, settings->max_contact_constraints, *this->broad_phase_layer_interface, *this->object_vs_broadphase_layer_filter, *this->object_vs_object_layer_filter);
    this->physics_system->SetGravity(JPH::Vec3(0.0, -9.8, 0.0));

    this->contact_listener = alloc_t<MyContactListener>();
    ::new (this->contact_listener) MyContactListener(this);
    this->physics_system->SetContactListener(this->contact_listener);
}

PhysicsWorld::~PhysicsWorld()
{
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