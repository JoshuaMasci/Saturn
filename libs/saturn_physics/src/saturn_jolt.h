#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Must be 16 byte aligned
typedef void *(*AllocateFunction)(size_t in_size);
typedef void (*FreeFunction)(void *in_block);
typedef void *(*AlignedAllocateFunction)(size_t in_size, size_t in_alignment);
typedef void (*AlignedFreeFunction)(void *in_block);
typedef void *(*ReallocateFunction)(void *inBlock, size_t old_size, size_t new_size);

typedef struct AllocationFunctions {
    AllocateFunction alloc;
    FreeFunction free;
    AlignedAllocateFunction aligned_alloc;
    AlignedFreeFunction aligned_free;
    ReallocateFunction realloc;
} AllocationFunctions;

typedef uint64_t ShapeHandle;
const ShapeHandle INVALID_SHAPE_HANDLE = 0;

typedef uint32_t BodyHandle;
typedef uint32_t CharacterHandle;
typedef uint16_t ObjectLayer;
typedef uint32_t MotionType;

void init(const AllocationFunctions *functions);
void deinit();

// Shape functions
ShapeHandle create_sphere_shape(float radius, float density);
ShapeHandle create_box_shape(const float half_extent[3], float density);
ShapeHandle create_cylinder_shape(float half_height, float radius, float density);
ShapeHandle create_capsule_shape(float half_height, float radius, float density);
ShapeHandle
create_mesh_shape(const float positions[][3], size_t position_count, const uint32_t *indices, size_t indices_count);
void destroy_shape(ShapeHandle handle);

// World Structs and functions
typedef struct PhysicsWorldSettings {
    uint32_t max_bodies;
    uint32_t num_body_mutexes;
    uint32_t max_body_pairs;
    uint32_t max_contact_constraints;
    uint32_t temp_allocation_size;
} PhysicsWorldSettings;

typedef struct Transform {
    float position[3];
    float rotation[4];
} Transform;

typedef struct PhysicsWorld PhysicsWorld;

typedef struct RayCastHit {
    BodyHandle body;
    uint32_t shape_index;
    float distance;
    float ws_position[3];
    float ws_normal[3];
    uint64_t body_user_data;
    uint64_t shape_user_data;
} RayCastHit;
typedef void (*RayCastCallback)(void *, RayCastHit);

typedef struct ShapeCastHit {
    BodyHandle body;
    uint32_t shape_index;
    uint64_t body_user_data;
    uint64_t shape_user_data;
} ShapeCastHit;
typedef void (*ShapeCastCallback)(void *, ShapeCastHit);

PhysicsWorld *create_physics_world(const PhysicsWorldSettings *settings);
void destroy_physics_world(PhysicsWorld *ptr);
void update_physics_world(PhysicsWorld *ptr, float delta_time, int collision_steps);

bool
ray_cast_closest(PhysicsWorld *ptr, ObjectLayer object_layer_pattern, const float origin[3], const float direction[3],
                 RayCastHit *hit_result);
void ray_cast_all(PhysicsWorld *ptr, ObjectLayer object_layer_pattern, const float origin[3], const float direction[3],
                  RayCastCallback callback, void *callback_data);
void shape_cast(PhysicsWorld *ptr, ObjectLayer object_layer_pattern, ShapeHandle shape, const Transform *transform,
                ShapeCastCallback callback, void *callback_data);

typedef struct BodySettings {
    ShapeHandle shape;
    float position[3];
    float rotation[4];
    float linear_velocity[3];
    float angular_velocity[3];
    uint64_t user_data;
    ObjectLayer object_layer;
    MotionType motion_type;
    bool is_sensor;
    bool allow_sleep;
    float friction;
    float linear_damping;
    float angular_damping;
    float gravity_factor;
} BodySettings;

typedef struct BodyHandleList {
    BodyHandle *ptr;
    uint64_t count;
} BodyHandleList;

typedef struct CharacterSettings {
    ShapeHandle shape;
    float position[3];
    float rotation[4];
    ShapeHandle inner_body_shape;
    ObjectLayer inner_body_layer;
} CharacterSettings;

typedef uint32_t GroundState;

// Body Functions
BodyHandle create_body(PhysicsWorld *ptr, const BodySettings *body_settings);
void destroy_body(PhysicsWorld *ptr, BodyHandle handle);

Transform get_body_transform(PhysicsWorld *ptr, BodyHandle handle);
void set_body_transform(PhysicsWorld *ptr, BodyHandle handle, const Transform *transform);
void get_body_linear_velocity(PhysicsWorld *ptr, BodyHandle handle, float *velocity_ptr);
void set_body_linear_velocity(PhysicsWorld *ptr, BodyHandle handle, const float velocity[3]);
void get_body_angular_velocity(PhysicsWorld *ptr, BodyHandle handle, float *velocity_ptr);
void set_body_angular_velocity(PhysicsWorld *ptr, BodyHandle handle, const float velocity[3]);

BodyHandleList get_body_contact_list(PhysicsWorld *ptr, BodyHandle handle);
void set_body_gravity_mode_radial(PhysicsWorld *ptr, BodyHandle handle, float gravity_strength);
void set_body_gravity_mode_vector(PhysicsWorld *ptr, BodyHandle handle, const float gravity[3]);
void clear_body_gravity_mode(PhysicsWorld *ptr, BodyHandle handle);

// Character Functions
CharacterHandle add_character(PhysicsWorld *ptr, const CharacterSettings *character_settings);
void destroy_character(PhysicsWorld *ptr, CharacterHandle handle);

void set_character_rotation(PhysicsWorld *ptr, CharacterHandle handle, const float rotation[4]);
Transform get_character_transform(PhysicsWorld *ptr, CharacterHandle handle);
void set_character_transform(PhysicsWorld *ptr, CharacterHandle handle, Transform *transform);
void get_character_linear_velocity(PhysicsWorld *ptr, CharacterHandle handle, float *velocity_ptr);
void set_character_linear_velocity(PhysicsWorld *ptr, CharacterHandle handle, const float velocity[3]);
void get_character_ground_velocity(PhysicsWorld *ptr, CharacterHandle handle, float *velocity_ptr);
GroundState get_character_ground_state(PhysicsWorld *ptr,
                                       CharacterHandle handle);

#ifdef __cplusplus
}
#endif
