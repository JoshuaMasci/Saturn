#pragma once

#include "saturn_jolt.h"
#include <Jolt/Core/UnorderedMap.h>

class ShapePool {
private:
    JPH::UnorderedMap<ShapeHandle, JPH::ShapeRefC> pool;
    ShapeHandle next_handle = 1;

public:
    ShapeHandle insert(const JPH::ShapeRefC &shape) {
        ShapeHandle handle = this->next_handle++;
        this->pool.emplace(handle, shape);
        return handle;
    }

    JPH::ShapeRefC get(ShapeHandle handle) {
        return this->pool[handle];
    }

    void remove(ShapeHandle handle) {
        this->pool.erase(handle);
    }
};