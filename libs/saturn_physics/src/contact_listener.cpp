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

    if (this->physics_world->contact_lists.find(inBody1ID) != this->physics_world->contact_lists.end()) {
        this->physics_world->contact_lists[inBody1ID].add(inBody2ID);
    }

    if (this->physics_world->contact_lists.find(inBody2ID) != this->physics_world->contact_lists.end()) {
        this->physics_world->contact_lists[inBody2ID].add(inBody1ID);
    }
}

void MyContactListener::OnContactPersisted(const JPH::Body &inBody1, const JPH::Body &inBody2,
                                           const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) {
}

void MyContactListener::OnContactRemoved(const JPH::SubShapeIDPair &inSubShapePair) {
    auto inBody1ID = inSubShapePair.GetBody1ID();
    auto inBody2ID = inSubShapePair.GetBody2ID();

    if (this->physics_world->contact_lists.find(inBody1ID) != this->physics_world->contact_lists.end()) {
        this->physics_world->contact_lists[inBody1ID].remove(inBody2ID);
    }

    if (this->physics_world->contact_lists.find(inBody2ID) != this->physics_world->contact_lists.end()) {
        this->physics_world->contact_lists[inBody2ID].remove(inBody1ID);
    }
}