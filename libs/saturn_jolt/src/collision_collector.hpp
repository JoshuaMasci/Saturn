#pragma once

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Body/BodyInterface.h>
#include <Jolt/Physics/Collision/Shape/Shape.h>

#include "saturn_jolt.h"
#include "body.hpp"

class ShapeCastCallbackCollisionCollector : public JPH::CollideShapeCollector {
public:
    ShapeCastCallbackCollisionCollector(ShapeCastCallback callback, void *callback_data,
                                        JPH::BodyInterface &body_interface) : body_interface(body_interface) {
        this->callback = callback;
        this->callback_data = callback_data;
    }

    // See: CollectorType::AddHit
    void AddHit(const ResultType &inResult) override {
        ShapeCastHit hit;

		Body *body_ptr = reinterpret_cast<Body *>(this->body_interface.GetUserData(inResult.mBodyID2));
		hit.body_ptr = body_ptr;
		hit.body_user_data = body_ptr->getUserData();

		auto shape_info = body_ptr->getSubShapeInfo(inResult.mSubShapeID2);
		hit.shape_index = shape_info.index;
		hit.shape_user_data = shape_info.user_data;

        this->callback(this->callback_data, hit);
    }

private:
    ShapeCastCallback callback;
    void *callback_data;
    JPH::BodyInterface &body_interface;
};

