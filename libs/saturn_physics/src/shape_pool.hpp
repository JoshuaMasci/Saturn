#pragma once

#include "saturn_jolt.h"
#include <Jolt/Core/UnorderedMap.h>

class ShapePool {
private:
    JPH::UnorderedMap<ShapeHandle, JPH::Ref<JPH::Shape>> pool;
    ShapeHandle next_handle = 1;

public:
    ShapeHandle insert(const JPH::Ref<JPH::Shape> &shape) {
        ShapeHandle handle = this->next_handle++;
        this->pool.emplace(handle, shape);
        return handle;
    }

    JPH::Ref<JPH::Shape> get(ShapeHandle handle) {
        return this->pool[handle];
    }

    void remove(ShapeHandle handle) {
        this->pool.erase(handle);
    }
};