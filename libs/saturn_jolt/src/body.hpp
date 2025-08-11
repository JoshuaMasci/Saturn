#pragma once

#include "saturn_jolt.h"
#include "math.hpp"
#include "object_pool.hpp"

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>

#include <Jolt/Physics/EActivation.h>
#include <variant>

struct SubShapeInfo {
    uint32_t index;
    UserData user_data;
};

struct SubShape {
    JPH::Ref<JPH::Shape> shape;
    JPH::Vec3 position;
    JPH::Quat rotation;
    UserData user_data;
};

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

    void addForce(JPH::Vec3 force, JPH::EActivation activation);

    void addTorque(JPH::Vec3 torque, JPH::EActivation activation);

	void addImpulse(JPH::Vec3 impulse);

	void addAngularImpulse(JPH::Vec3 angular_impulse);

    SubShapeIndex addShape(const SubShape &shape);

    void removeShape(SubShapeIndex index);

    void updateShape(SubShapeIndex index, SubShape shape);

    void updateShapeTransform(SubShapeIndex index, JPH::Vec3 position,
                              JPH::Quat rotation);

    void removeAllShape();

    void commitShapeChanges();

    JPH::BodyCreationSettings getCreateSettings();

    UserData getUserData() const { return this->user_data; }

    SubShapeInfo getSubShapeInfo(JPH::SubShapeID id) const;


    JPH::BodyID body_id;
    World *world_ptr = nullptr;

private:

    ObjectPool<SubShapeIndex, SubShape> subshapes;

    JPH::Ref<JPH::Shape> body_shape;

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
	float max_linear_velocity;
	float max_angular_velocity;
};
