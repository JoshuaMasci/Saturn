#include "gravity_step_listener.hpp"

#include <Jolt/Physics/PhysicsSystem.h>
#include "physics_world.hpp"

GravityStepListener::GravityStepListener(PhysicsWorld *physics_world) {
    this->physics_world = physics_world;
}

void GravityStepListener::OnStep(float delta_time, JPH::PhysicsSystem &physics_system) {
    JPH::BodyInterface &body_interface = physics_system.GetBodyInterfaceNoLock();

    for (auto contact_list: this->physics_world->contact_lists) {
        JPH::Real gravity_strength = 24500; //9.8 m/s2 at surface of 50m radius sphere
        JPH::RVec3 gravity_position = body_interface.GetPosition(contact_list.first);

        for (JPH::BodyID bodyId: contact_list.second.get_id_list()) {
            if (body_interface.IsActive(bodyId)) {
                JPH::RVec3 body_position = body_interface.GetPosition(bodyId);
                float body_gravity_factor = body_interface.GetGravityFactor(bodyId);
                JPH::RVec3 difference = gravity_position - body_position;
                JPH::Real distance2 = difference.LengthSq();
                JPH::Vec3 gravity_velocity = difference.Normalized() * (gravity_strength / distance2);
                gravity_velocity *= body_gravity_factor;
                gravity_velocity *= delta_time;
                body_interface.AddLinearVelocity(bodyId, gravity_velocity);
            }
        }

    }
}