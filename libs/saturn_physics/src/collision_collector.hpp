#pragma once

#include "saturn_jolt.h"

class ShapeCastCallbackCollisionCollector : public JPH::CollideShapeCollector {
public:
    ShapeCastCallbackCollisionCollector(ShapeCastCallback callback, void *callback_data,
                                        JPH::BodyInterface &body_interface) : body_interface(body_interface) {
        this->callback = callback;
        this->callback_data = callback_data;
    }

    // See: CollectorType::AddHit
    virtual void AddHit(const ResultType &inResult) override {
        ShapeCastHit hit;
        hit.body = inResult.mBodyID2.GetIndexAndSequenceNumber();
        hit.body_user_data = body_interface.GetUserData(inResult.mBodyID2);
        hit.shape_index = 0;
        hit.shape_user_data = 0;
        this->callback(this->callback_data, hit);
    }

private:
    ShapeCastCallback callback;
    void *callback_data;
    JPH::BodyInterface &body_interface;
};

