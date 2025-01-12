#include "world.hpp"

#include "body.hpp"

World::World(const WorldSettings *settings)
        : temp_allocator(settings->temp_allocation_size), job_system(1024) {
    this->broad_phase_layer_interface = alloc_t<BroadPhaseLayerInterfaceImpl>();
    ::new(this->broad_phase_layer_interface) BroadPhaseLayerInterfaceImpl();

    this->object_vs_broadphase_layer_filter =
            alloc_t<ObjectVsBroadPhaseLayerFilterImpl>();
    ::new(this->object_vs_broadphase_layer_filter)
            ObjectVsBroadPhaseLayerFilterImpl();

    this->object_vs_object_layer_filter =
            alloc_t<AnyMatchObjectLayerPairFilter>();
    ::new(this->object_vs_object_layer_filter) AnyMatchObjectLayerPairFilter();

    this->physics_system = alloc_t<JPH::PhysicsSystem>();
    ::new(this->physics_system) JPH::PhysicsSystem();
    this->physics_system->Init(settings->max_bodies, settings->num_body_mutexes, settings->max_body_pairs,
                               settings->max_contact_constraints, *this->broad_phase_layer_interface,
                               *this->object_vs_broadphase_layer_filter, *this->object_vs_object_layer_filter);

    this->physics_system->SetGravity(JPH::Vec3(0.0, 0.0, 0.0));
}

World::~World() {
    //TODO: remove all bodies from the world

    this->physics_system->~PhysicsSystem();
    free_t(this->physics_system);

    this->broad_phase_layer_interface->~BroadPhaseLayerInterfaceImpl();
    free_t(this->broad_phase_layer_interface);

    this->object_vs_broadphase_layer_filter->~ObjectVsBroadPhaseLayerFilterImpl();
    free_t(this->object_vs_broadphase_layer_filter);

    this->object_vs_object_layer_filter->~AnyMatchObjectLayerPairFilter();
    free_t(this->object_vs_object_layer_filter);
}

void World::update(float delta_time, int collision_steps) {
    auto error = this->physics_system->Update(delta_time, collision_steps, &this->temp_allocator, &this->job_system);
    if (error != JPH::EPhysicsUpdateError::None) {
        printf("Physics Update Error: %d", error);
    }
}

void World::addBody(Body *body) {
    JPH::BodyInterface &body_interface = this->physics_system->GetBodyInterface();
    body->body_id = body_interface.CreateAndAddBody(body->getCreateSettings(), JPH::EActivation::Activate);
    body->world_ptr = this;
}

void World::removeBody(Body *body) {
    if (body != nullptr && body->world_ptr == this) {
        JPH::BodyInterface &body_interface = this->physics_system->GetBodyInterface();
        body_interface.RemoveBody(body->body_id);
        body->body_id = JPH::BodyID();
        body->world_ptr = nullptr;
    }
}
