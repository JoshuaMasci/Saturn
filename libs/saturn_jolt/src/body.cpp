#include "body.hpp"

#include "world.hpp"
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/EmptyShape.h>

#include <utility>

Body::Body(const BodySettings *settings) {
    this->body_shape = JPH::EmptyShapeSettings().Create().Get();

    this->position = load_rvec3(settings->position);
    this->rotation = load_quat(settings->rotation);
    this->linear_velocity = load_vec3(settings->linear_velocity);
    this->angular_velocity = load_vec3(settings->angular_velocity);

    // Sets user_data to ptr so this object can always be accessed
    this->user_data = (uint64_t) this;
    this->object_layer = settings->object_layer;
    this->motion_type = settings->motion_type;
    this->allow_sleep = settings->allow_sleep;
    this->friction = settings->friction;
    this->linear_damping = settings->linear_damping;
    this->angular_damping = settings->angular_damping;
    this->gravity_factor = settings->gravity_factor;
}

Body::~Body() {
    if (this->world_ptr != nullptr) {
        this->world_ptr->removeBody(this);
    }
}

World *Body::getWorld() const {
    return this->world_ptr;
}

JPH::RVec3 Body::getPosition() {
    if (this->world_ptr != nullptr) {
        this->position = this->world_ptr->physics_system->GetBodyInterface().GetPosition(this->body_id);
    }

    return this->position;
}

JPH::Quat Body::getRotation() {
    if (this->world_ptr != nullptr) {
        this->rotation = this->world_ptr->physics_system->GetBodyInterface().GetRotation(this->body_id);
    }

    return this->rotation;
}

void Body::setTransform(const JPH::RVec3 new_position, const JPH::Quat new_rotation) {
    this->position = new_position;
    this->rotation = new_rotation;

    if (this->world_ptr != nullptr) {
        this->world_ptr->physics_system->GetBodyInterface().SetPositionAndRotationWhenChanged(this->body_id, this->position, this->rotation, JPH::EActivation::Activate);
    }
}

JPH::Vec3 Body::getLinearVelocity() {
    if (this->world_ptr != nullptr) {
        this->linear_velocity = this->world_ptr->physics_system->GetBodyInterface().GetLinearVelocity(this->body_id);
    }

    return this->linear_velocity;
}

JPH::Vec3 Body::getAngularVelocity() {
    if (this->world_ptr != nullptr) {
        this->angular_velocity = this->world_ptr->physics_system->GetBodyInterface().GetAngularVelocity(this->body_id);
    }

    return this->angular_velocity;
}

void Body::setVelocity(const JPH::Vec3 new_linear_velocity, const JPH::Vec3 new_angular_velocity) {
    this->linear_velocity = new_linear_velocity;
    this->angular_velocity = new_angular_velocity;

    if (this->world_ptr != nullptr) {
        this->world_ptr->physics_system->GetBodyInterface().SetLinearAndAngularVelocity(this->body_id, this->linear_velocity, this->angular_velocity);
    }
}

JPH::BodyCreationSettings Body::getCreateSettings() {
    auto settings = JPH::BodyCreationSettings();

    //TODO: determine what base shape should be used based on what child shapes have been added
    settings.SetShape(this->body_shape);

    settings.mPosition = position;
    settings.mRotation = rotation;
    settings.mLinearVelocity = linear_velocity;
    settings.mAngularVelocity = angular_velocity;
    settings.mUserData = user_data;
    settings.mObjectLayer = object_layer;

    switch (motion_type) {
        case 0:
            settings.mMotionType = JPH::EMotionType::Static;
            break;
        case 1:
            settings.mMotionType = JPH::EMotionType::Kinematic;
            break;
        case 2:
            settings.mMotionType = JPH::EMotionType::Dynamic;
            break;
    }

    settings.mIsSensor = false;
    settings.mAllowSleeping = allow_sleep;
    settings.mFriction = friction;
    settings.mGravityFactor = gravity_factor;
    settings.mLinearDamping = linear_damping;
    settings.mAngularDamping = angular_damping;

    return settings;
}

SubShapeIndex Body::addShape(const SubShape &shape) {
    return this->subshapes.insert(shape);
}

void Body::removeShape(SubShapeIndex index) {
    this->subshapes.remove(index);
}


void Body::updateShape(SubShapeIndex index, SubShape shape) {
    this->subshapes.get(index) = std::move(shape);
}

void Body::updateShapeTransform(SubShapeIndex index, JPH::Vec3 new_position, JPH::Quat new_rotation) {
    auto ref = this->subshapes.get(index);
    ref.position = new_position;
    ref.rotation = new_rotation;
}

void Body::removeAllShape() {
    this->subshapes.clear();
}

void Body::commitShapeChanges() {
    auto shape_ref = JPH::EmptyShapeSettings().Create().Get();

    //TODO: not rebuild the whole compound shape during this step
    if (this->subshapes.size() != 0) {
        auto static_shape_settings = JPH::StaticCompoundShapeSettings();

        for (const auto &pair: this->subshapes) {
            static_shape_settings.AddShape(pair.second.position, pair.second.rotation, pair.second.shape, pair.second.user_data);
        }

        shape_ref = static_shape_settings.Create().Get();
    }

    this->body_shape = shape_ref;

    if (this->world_ptr != nullptr) {
        this->world_ptr->physics_system->GetBodyInterface().SetShape(this->body_id, shape_ref, true, JPH::EActivation::DontActivate);
    }
}


