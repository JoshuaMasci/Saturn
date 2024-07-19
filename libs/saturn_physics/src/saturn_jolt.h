#pragma once
#include <stdbool.h>
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

    // Shape functions
    typedef uint64_t SPH_ShapeHandle;
    SPH_ShapeHandle SPH_Shape_Sphere(float radius, float density);
    SPH_ShapeHandle SPH_Shape_Box(const float half_extent[3], float density);
    SPH_ShapeHandle SPH_Shape_Cylinder(float half_height, float radius, float density);
    SPH_ShapeHandle SPH_Shape_Capsule(float half_height, float radius, float density);
    void SPH_Shape_Destroy(SPH_ShapeHandle handle);

    // World functions
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

    typedef struct SPH_BodySettings
    {
        SPH_ShapeHandle shape;
        float position[3];
        float rotation[4];
        float linear_velocity[3];
        float angular_velocity[3];
        uint64_t user_data;
        uint32_t motion_type;
        bool is_sensor;
        bool allow_sleep;
        float friction;
        float gravity_factor;
    } SPH_BodySettings;

    typedef struct SPH_Transform
    {
        float position[3];
        float rotation[4];
    } SPH_Transform;

    typedef uint32_t SPH_BodyHandle;
    SPH_BodyHandle SPH_PhysicsWorld_Body_Create(SPH_PhysicsWorld *ptr, const SPH_BodySettings *body_settings);
    void SPH_PhysicsWorld_Body_Destroy(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle);
    SPH_Transform SPH_PhysicsWorld_Body_GetTransform(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle);

#ifdef __cplusplus
}
#endif