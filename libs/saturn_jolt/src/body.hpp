#pragma once

#include "saturn_jolt.h"
#include "math.hpp"

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>

class World;

class Body {
public:
    explicit Body(const BodySettings *settings);

    ~Body();

    World *getWorld() const;

    JPH::RVec3 getPosition();

    JPH::Quat getRotation();

    void setTransform(JPH::RVec3 new_position, JPH::Quat new_rotation);

    JPH::Vec3 getLinearVelocity();

    JPH::Vec3 getAngularVelocity();

    void setVelocity(JPH::Vec3 new_linear_velocity, JPH::Vec3 new_angular_velocity);

    JPH::BodyCreationSettings getCreateSettings();

    JPH::BodyID body_id;
    World *world_ptr = nullptr;

private:
    JPH::Ref<JPH::Shape> shape;

    JPH::RVec3 position{};
    JPH::Quat rotation{};

    JPH::Vec3 linear_velocity{};
    JPH::Vec3 angular_velocity{};

    UserData user_data;
    ObjectLayer object_layer;
    MotionType motion_type;
    bool allow_sleep;
    float friction;
    float linear_damping;
    float angular_damping;
    float gravity_factor;
};