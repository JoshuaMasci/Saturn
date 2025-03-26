#pragma once

// Needed for C interface
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Init functions
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

void init(const AllocationFunctions *functions);
void deinit();

// Base types
#ifdef JPH_DOUBLE_PRECISION
typedef double RVec3[3];
#else
typedef float RVec3[3];
#endif

typedef float Vec2[2];
typedef float Vec3[3];
typedef float Vec4[4];
typedef float Quat[4];
typedef float Mat44[16];

typedef struct Transform {
	RVec3 position;
	Quat rotation;
} Transform;

typedef struct Velocity {
	Vec3 linear;
	Vec3 angular;
} Velocity;

typedef struct World World;
typedef struct Body Body;
typedef struct SoftBody SoftBody;
typedef uint64_t Shape;
const Shape InvalidShape = UINT64_MAX;

typedef uint64_t UserData;
typedef uint32_t SubShapeIndex;

typedef uint16_t ObjectLayer;
typedef uint32_t MotionType;

// Renderer functions
typedef struct Color {
	uint8_t r;
	uint8_t g;
	uint8_t b;
	uint8_t a;
} Color __attribute__((aligned(4)));
Color color_from_u32(uint32_t value);

typedef struct Vertex {
	Vec3 position;
	Vec3 normal;
	Vec2 uv;
	Color color;
} Vertex;

typedef Vertex Triangle[3];
typedef uint32_t MeshPrimitive;

typedef struct DrawLineData {
	RVec3 from;
	RVec3 to;
	Color color;
} DrawLineData;
typedef void (*DrawLineCallback)(void *, DrawLineData);

typedef struct DrawTriangleData {
	RVec3 v1;
	RVec3 v2;
	RVec3 v3;
	Color color;
	bool shadow;
} DrawTriangleData;
typedef void (*DrawTriangleCallback)(void *, DrawTriangleData);

typedef struct DrawTextData {
	RVec3 Position;
	const char *text;
	size_t text_len;
	float height;
	Color color;
} DrawTextData;
typedef void (*DrawText3DCallback)(void *, DrawTextData);

typedef void (*CreateTriangleMeshCallback)(void *, MeshPrimitive, const Triangle *, size_t);
typedef void (*CreateIndexedMeshCallback)(void *, MeshPrimitive, const Vertex *, size_t, const uint32_t *, size_t);

typedef enum CullMode {
	CULL_MODE_BACK = 0,
	CULL_MODE_FRONT = 1,
	CULL_MODE_OFF = 2,
} CullMode;

typedef enum DrawMode {
	DRAW_MODE_SOLID = 0,
	DRAW_MODE_WIREFRAME = 1,
} DrawMode;

typedef struct DrawGeometryData {
	MeshPrimitive mesh;
	Color color;
	CullMode cull_mode;
	DrawMode draw_mode;
	Mat44 model_matrix;
} DrawGeometryData;
typedef void (*DrawGeometryCallback)(void *, DrawGeometryData);

typedef void (*FreeMeshPrimitive)(void *, MeshPrimitive);

typedef struct DebugRendererCallbacks {
	void *ptr;
	DrawLineCallback draw_line;
	DrawTriangleCallback draw_triangle;
	DrawText3DCallback draw_text;
	CreateTriangleMeshCallback create_triangle_mesh;
	CreateIndexedMeshCallback create_indexed_mesh;
	DrawGeometryCallback draw_geometry;
	FreeMeshPrimitive free_mesh;
} DebugRendererCallbacks;

void debugRendererCreate(DebugRendererCallbacks data);
void debugRendererDestroy();
void debugRendererBuildFrame(World *world_ptr, Transform transform);

// Structs
typedef struct WorldSettings {
	uint32_t max_bodies;
	uint32_t num_body_mutexes;
	uint32_t max_body_pairs;
	uint32_t max_contact_constraints;

	// TODO: both of these should be replaced with global pool
	uint32_t temp_allocation_size;
	uint16_t threads;
} WorldSettings;

typedef struct World World;
typedef struct Body Body;

typedef struct MassProperties {
	float mass;
	float inertia_tensor[16];
} MassProperties;

typedef struct RayCastHit {
	Body *body_ptr;
	SubShapeIndex shape_index;
	float distance;
	RVec3 ws_position;
	Vec3 ws_normal;
	UserData body_user_data;
	UserData shape_user_data;
} RayCastHit;
typedef void (*RayCastCallback)(void *, RayCastHit);

typedef struct ShapeCastHit {
	Body *body_ptr;
	SubShapeIndex shape_index;
	UserData body_user_data;
	UserData shape_user_data;
} ShapeCastHit;
typedef void (*ShapeCastCallback)(void *, ShapeCastHit);

typedef struct BodySettings {
	Shape shape;
	RVec3 position;
	Quat rotation;
	Vec3 linear_velocity;
	Vec3 angular_velocity;
	UserData user_data;
	ObjectLayer object_layer;
	MotionType motion_type;
	bool allow_sleep;
	float friction;
	float linear_damping;
	float angular_damping;
	float gravity_factor;
} BodySettings;

typedef struct SubShapeSettings {
	Shape shape;
	Vec3 position;
	Quat rotation;
} SubShapeSettings;

// Shape functions
Shape shapeCreateSphere(float radius, float density, UserData user_data);
Shape shapeCreateBox(const Vec3 half_extent, float density, UserData user_data);
Shape shapeCreateCylinder(float half_height, float radius, float density, UserData user_data);
Shape shapeCreateCapsule(float half_height, float radius, float density, UserData user_data);
Shape shapeCreateConvexHull(const Vec3 positions[], size_t position_count, float density, UserData user_data);
Shape shapeCreateMesh(const Vec3 positions[], size_t position_count, const uint32_t *indices, size_t indices_count, const MassProperties *mass_properties, UserData user_data);
Shape shapeCreateCompound(const SubShapeSettings sub_shapes[], size_t sub_shape_count, UserData user_data);
void shapeDestroy(Shape shape);

MassProperties shapeGetMassProperties(Shape shape);

// World functions
World *worldCreate(const WorldSettings *settings);
void worldDestroy(World *world_ptr);
void worldUpdate(World *world_ptr, float delta_time, int collision_steps);

void worldAddBody(World *world_ptr, Body *body_ptr);
void worldRemoveBody(World *world_ptr, Body *body_ptr);

bool worldCastRayCloset(World *world_ptr, ObjectLayer object_layer_pattern, const RVec3 origin, const Vec3 direction, RayCastHit *hit_result);
bool worldCastRayClosetIgnoreBody(World *world_ptr, ObjectLayer object_layer_pattern, Body *ignore_body_ptr, const RVec3 origin, const Vec3 direction, RayCastHit *hit_result);
void worldCastRayAll(World *world_ptr, ObjectLayer object_layer_pattern, const RVec3 origin, const Vec3 direction, RayCastCallback callback, void *callback_data);
void worldCastShape(World *world_ptr, ObjectLayer object_layer_pattern, Shape shape, const Transform *c_transform, ShapeCastCallback callback, void *callback_data);

// Body functions
Body *bodyCreate(const BodySettings *settings);
void bodyDestroy(Body *body_ptr);
World *bodyGetWorld(Body *body_ptr);

Transform bodyGetTransform(Body *body_ptr);
void bodySetTransform(Body *body_ptr, const Transform *c_transform);
Velocity bodyGetVelocity(Body *body_ptr);
void bodySetVelocity(Body *body_ptr, const Velocity *c_velocity);

SubShapeIndex bodyAddShape(Body *body_ptr, Shape shape, const Vec3 position, const Quat rotation, UserData user_data);
void bodyRemoveShape(Body *body_ptr, SubShapeIndex index);
void bodyUpdateShapeTransform(Body *body_ptr, SubShapeIndex index, const Vec3 position, const Quat rotation);
void bodyRemoveAllShapes(Body *body_ptr);
void bodyCommitShapeChanges(Body *body_ptr);

#ifdef __cplusplus
}
#endif
