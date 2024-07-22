#include "contact_listener.hpp"

#include "physics_world.hpp"

#include <iostream>

MyContactListener::MyContactListener(PhysicsWorld *physics_world) {
    this->physics_world = physics_world;
}

// See: ContactListener
JPH::ValidateResult
MyContactListener::OnContactValidate(const JPH::Body &inBody1, const JPH::Body &inBody2, JPH::RVec3Arg inBaseOffset,
                                     const JPH::CollideShapeResult &inCollisionResult) {
    return JPH::ValidateResult::AcceptAllContactsForThisBodyPair;
}

void MyContactListener::OnContactAdded(const JPH::Body &inBody1, const JPH::Body &inBody2,
                                       const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) {
    auto inBody1ID = inBody1.GetID();
    auto inBody2ID = inBody2.GetID();

    if (this->physics_world->volume_list.find(inBody1ID) != this->physics_world->volume_list.end()) {
        this->physics_world->volume_list[inBody1ID].emplace(inBody2ID);
        std::cout << "A contact body1 was added: " << this->physics_world->volume_list[inBody1ID].size() << std::endl;
    }

    if (this->physics_world->volume_list.find(inBody2ID) != this->physics_world->volume_list.end()) {
        this->physics_world->volume_list[inBody2ID].emplace(inBody1ID);
        std::cout << "A contact body2 was added: " << this->physics_world->volume_list[inBody2ID].size() << std::endl;
    }
}

void MyContactListener::OnContactPersisted(const JPH::Body &inBody1, const JPH::Body &inBody2,
                                           const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) {
}

void MyContactListener::OnContactRemoved(const JPH::SubShapeIDPair &inSubShapePair) {
    auto inBody1ID = inSubShapePair.GetBody1ID();
    auto inBody2ID = inSubShapePair.GetBody2ID();

    if (this->physics_world->volume_list.find(inBody1ID) != this->physics_world->volume_list.end()) {
        this->physics_world->volume_list[inBody1ID].erase(inBody2ID);
        std::cout << "A contact body1 was removed: " << this->physics_world->volume_list[inBody1ID].size() << std::endl;
    }

    if (this->physics_world->volume_list.find(inBody2ID) != this->physics_world->volume_list.end()) {
        this->physics_world->volume_list[inBody2ID].erase(inBody1ID);
        std::cout << "A contact body2 was removed: " << this->physics_world->volume_list[inBody2ID].size() << std::endl;
    }
}