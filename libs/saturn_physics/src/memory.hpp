#pragma once

#include <Jolt/Jolt.h>
#include <Jolt/Core/STLAllocator.h>
#include <Jolt/Core/UnorderedMap.h>
#include <Jolt/Core/UnorderedSet.h>

template <class T>
T *alloc_t()
{
    return static_cast<T *>(JPH::Allocate(sizeof(T)));
}

template <class T>
void free_t(T *ptr)
{
    JPH::Free((void *)ptr);
}

template <typename T>
using JoltVector = std::vector<T, JPH::STLAllocator<T>>;