#pragma once

#include <Jolt/Core/UnorderedMap.h>
#include <iterator>

template<typename I, typename T>
class ObjectPool {
private:
    JPH::UnorderedMap<I, T> pool;
    I next_handle = 1;

public:
    // Insert a new shape and return its handle (index)
    I insert(const T &object) {
        I handle = this->next_handle++;
        this->pool[handle] = object;
        return handle;
    }

    T &get(I handle) {
		return this->pool.find(handle)->second;
    }

    const T &get(I handle) const {
        return this->pool.find(handle)->second;
    }

    void remove(I handle) {
        this->pool.erase(handle);
    }

    bool contains(I handle) const {
        return this->pool.find(handle) != this->end();
    }

    void clear() {
        this->pool.clear();
    }

    size_t size() const {
        return this->pool.size();
    }

    // Iterator support: Allow for iterating over pool items
    using iterator = typename JPH::UnorderedMap<I, T>::iterator;
    using const_iterator = typename JPH::UnorderedMap<I, T>::const_iterator;

    iterator begin() {
        return pool.begin();
    }

    iterator end() {
        return pool.end();
    }

    const_iterator begin() const {
        return pool.begin();
    }

    const_iterator end() const {
        return pool.end();
    }
};

