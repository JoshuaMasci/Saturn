#include "gravity_step_listener.hpp"

#include "physics_world.hpp"
#include <Jolt/Physics/PhysicsSystem.h>

GravityStepListener::GravityStepListener(PhysicsWorld *physics_world) {
  this->physics_world = physics_world;
}

void GravityStepListener::OnStep(float delta_time, JPH::PhysicsSystem &physics_system) {
  JPH::BodyInterface &body_interface = physics_system.GetBodyInterfaceNoLock();

  for (auto volume_body : this->physics_world->volume_bodies) {
	if (volume_body.second.gravity_strength) {
	  JPH::Real gravity_strength = volume_body.second.gravity_strength.value();
	  JPH::RVec3 gravity_position =
		  body_interface.GetPosition(volume_body.first);

	  for (JPH::BodyID bodyId : volume_body.second.contact_list.get_id_list()) {
		if (body_interface.IsActive(bodyId)) {
		  JPH::RVec3 body_position = body_interface.GetPosition(bodyId);
		  float body_gravity_factor = body_interface.GetGravityFactor(bodyId);
		  JPH::RVec3 difference = gravity_position - body_position;
		  JPH::Real distance2 = difference.LengthSq();
		  JPH::Vec3 gravity_velocity =
			  difference.Normalized() * (gravity_strength / distance2);
		  gravity_velocity *= body_gravity_factor;
		  gravity_velocity *= delta_time;
		  body_interface.AddLinearVelocity(bodyId, gravity_velocity);
		}
	  }
	}
  }
}
