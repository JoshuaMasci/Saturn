#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // Must be 16 byte aligned
    typedef void *(*SPH_AllocateFunction)(size_t in_size);
    typedef void (*SPH_FreeFunction)(void *in_block);
    typedef void *(*SPH_AlignedAllocateFunction)(size_t in_size, size_t in_alignment);
    typedef void (*SPH_AlignedFreeFunction)(void *in_block);
    typedef struct SPH_AllocationFunctions
    {
        SPH_AllocateFunction alloc;
        SPH_FreeFunction free;
        SPH_AlignedAllocateFunction aligned_alloc;
        SPH_AlignedFreeFunction aligned_free;
    } SPH_AllocationFunctions;

    void SPH_Init(const SPH_AllocationFunctions *functions);
    void SPH_Deinit();

    typedef struct SPH_PhysicsWorldSettings
    {
        uint32_t max_bodies;
        uint32_t num_body_mutexes;
        uint32_t max_body_pairs;
        uint32_t max_contact_constraints;
        uint32_t temp_allocation_size;
    } SPH_PhysicsWorldSettings;
    typedef struct SPH_PhysicsWorld SPH_PhysicsWorld;
    SPH_PhysicsWorld *SPH_PhysicsWorld_Create(const SPH_PhysicsWorldSettings *settings);
    void SPH_PhysicsWorld_Destroy(SPH_PhysicsWorld *ptr);
    void SPH_PhysicsWorld_Update(SPH_PhysicsWorld *ptr, float inDeltaTime, int32_t inCollisionSteps);

#ifdef __cplusplus
}
#endif