#pragma once

#include "saturn_jolt.h"
#include <Jolt/Core/UnorderedMap.h>

class ShapePool {
private:
    JPH::UnorderedMap<Shape, JPH::Ref<JPH::Shape>> pool;
    Shape next_handle = 1;

public:
    Shape insert(const JPH::Ref<JPH::Shape> &shape) {
        Shape handle = this->next_handle++;
        this->pool[handle] = shape;
        return handle;
    }

    JPH::Ref<JPH::Shape> get(Shape handle) {
        return this->pool[handle];
    }

    void remove(Shape handle) {
        this->pool.erase(handle);
    }
};