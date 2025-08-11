#include "saturn_jolt.h"

#include <cstdio>
#include <iostream>
#include <thread>

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>

#include "memory.hpp"
#include "shape_pool.hpp"

#include "Jolt/Physics/Collision/Shape/BoxShape.h"
#include "Jolt/Physics/Collision/Shape/CapsuleShape.h"
#include "Jolt/Physics/Collision/Shape/ConvexHullShape.h"
#include "Jolt/Physics/Collision/Shape/CylinderShape.h"
#include "Jolt/Physics/Collision/Shape/MeshShape.h"
#include "Jolt/Physics/Collision/Shape/SphereShape.h"
#include "Jolt/Physics/Collision/Shape/StaticCompoundShape.h"
#include "body.hpp"
#include "mass_shape.hpp"
#include "world.hpp"

ShapePool *shape_pool = nullptr;
std::mutex shape_pool_mutex;

void init(const AllocationFunctions *functions) {
	if (functions != nullptr) {
		JPH::Allocate = functions->alloc;
		JPH::Free = functions->free;
		JPH::AlignedAllocate = functions->aligned_alloc;
		JPH::AlignedFree = functions->aligned_free;
		JPH::Reallocate = functions->realloc;
	} else {
		JPH::RegisterDefaultAllocator();
	}

	auto factory =
		static_cast<JPH::Factory *>(JPH::Allocate(sizeof(JPH::Factory)));
	::new (factory) JPH::Factory();
	JPH::Factory::sInstance = factory;
	JPH::RegisterTypes();

	JPH::MassShape::sRegister();

	shape_pool = new ShapePool();
}

void deinit() {
	debugRendererDestroy();
	shape_pool_mutex.lock();
	delete shape_pool;
	shape_pool_mutex.unlock();

	JPH::UnregisterTypes();
	JPH::Factory::sInstance->~Factory();
	JPH::Free((void *)JPH::Factory::sInstance);
	JPH::Factory::sInstance = nullptr;

	JPH::Allocate = nullptr;
	JPH::Free = nullptr;
	JPH::AlignedAllocate = nullptr;
	JPH::AlignedFree = nullptr;
}

#ifdef JPH_DEBUG_RENDERER
#include "callback_debug_renderer.hpp"

Color color_from_u32(uint32_t value) {
	Color color;
	color.r = (value >> 24) & 0xFF;
	color.g = (value >> 16) & 0xFF;
	color.b = (value >> 8) & 0xFF;
	color.a = value & 0xFF;
	return color;
}
#endif

void debugRendererCreate(DebugRendererCallbacks data) {
#ifdef JPH_DEBUG_RENDERER
	new CallbackDebugRenderer(data);
#endif
}
void debugRendererDestroy() {
#ifdef JPH_DEBUG_RENDERER
	delete JPH::DebugRenderer::sInstance;
#endif
}

void debugRendererBuildFrame(World *world_ptr, Transform camera_transform, const Body* const* ignore_bodies, const uint32_t ignore_bodies_count) {
#ifdef JPH_DEBUG_RENDERER
	if (JPH::DebugRenderer::sInstance != nullptr && world_ptr != nullptr) {
		auto renderer = dynamic_cast<CallbackDebugRenderer *>(JPH::DebugRenderer::sInstance);
		renderer->camera_position = loadRVec3(camera_transform.position);

		IgnoreListBodyDrawFilter draw_filter(ignore_bodies, ignore_bodies_count);

		JPH::BodyManager::DrawSettings settings;
		settings.mDrawShape = true;
		settings.mDrawShapeWireframe = true;
		settings.mDrawShapeColor = JPH::BodyManager::EShapeColor::SleepColor;
		world_ptr->physics_system->DrawBodies(settings, JPH::DebugRenderer::sInstance, &draw_filter);
	}
#endif
}

Shape shapeCreateSphere(float radius, float density, UserData user_data) {
	auto settings = JPH::SphereShapeSettings();
	settings.mRadius = radius;
	settings.mDensity = density;
	settings.mUserData = user_data;
	auto shape = settings.Create().Get();
	shape_pool_mutex.lock();
	auto shape_handle = shape_pool->insert(shape);
	shape_pool_mutex.unlock();
	return shape_handle;
}

Shape shapeCreateBox(const Vec3 half_extent, float density, UserData user_data) {
	auto settings = JPH::BoxShapeSettings();
	settings.mHalfExtent = loadVec3(half_extent);
	settings.mDensity = density;
	settings.mUserData = user_data;

	auto shape = settings.Create().Get();
	shape_pool_mutex.lock();
	auto shape_handle = shape_pool->insert(shape);
	shape_pool_mutex.unlock();
	return shape_handle;
}

Shape shapeCreateCylinder(float half_height, float radius, float density, UserData user_data) {
	auto settings = JPH::CylinderShapeSettings();
	settings.mHalfHeight = half_height;
	settings.mRadius = radius;
	settings.mDensity = density;
	settings.mUserData = user_data;

	auto shape = settings.Create().Get();
	shape_pool_mutex.lock();
	auto shape_handle = shape_pool->insert(shape);
	shape_pool_mutex.unlock();
	return shape_handle;
}

Shape shapeCreateCapsule(float half_height, float radius, float density, UserData user_data) {
	auto settings = JPH::CapsuleShapeSettings();
	settings.mHalfHeightOfCylinder = half_height;
	settings.mRadius = radius;
	settings.mDensity = density;
	settings.mUserData = user_data;

	auto shape = settings.Create().Get();
	shape_pool_mutex.lock();
	auto shape_handle = shape_pool->insert(shape);
	shape_pool_mutex.unlock();
	return shape_handle;
}

Shape shapeCreateConvexHull(const Vec3 positions[], size_t position_count, float density, UserData user_data) {
	JPH::Array<JPH::Vec3> point_list(position_count);
	for (size_t i = 0; i < position_count; i++) {
		point_list[i] = loadVec3(positions[i]);
	}
	auto settings = JPH::ConvexHullShapeSettings();
	settings.mPoints = point_list;
	settings.mDensity = density;
	settings.mUserData = user_data;

	auto shape = settings.Create().Get();
	shape_pool_mutex.lock();
	auto shape_handle = shape_pool->insert(shape);
	shape_pool_mutex.unlock();
	return shape_handle;
}

Shape shapeCreateMesh(const Vec3 positions[], size_t position_count, const uint32_t *indices, size_t indices_count, const MassProperties *mass_properties, UserData user_data) {
	JPH::MassProperties mass;

	JPH::VertexList vertex_list;
	for (size_t i = 0; i < position_count; i++) {
		vertex_list.push_back(loadFloat3(positions[i]));
	}

	JPH::IndexedTriangleList triangle_list;

	if (indices_count == 0) {
		for (int i = 0; i < position_count; i += 3) {
			triangle_list.push_back(JPH::IndexedTriangle(i + 0, i + 1, i + 2, 0));
		}
	} else {
		const size_t triangle_count = indices_count / 3;
		for (int i = 0; i < triangle_count; i++) {
			const size_t offset = i * 3;
			triangle_list.push_back(JPH::IndexedTriangle(
				indices[offset + 0], indices[offset + 1], indices[offset + 2], 0));
		}
	}

	auto settings = JPH::MeshShapeSettings(vertex_list, triangle_list);
	settings.mUserData = user_data;

	auto shape = settings.Create().Get();

	if (mass_properties != nullptr) {
		JPH::MassProperties override_mass;
		override_mass.mMass = mass_properties->mass;
		override_mass.mInertia = JPH::Mat44::sLoadFloat4x4(reinterpret_cast<const JPH::Float4 *>(mass_properties->inertia_tensor));
		shape = JPH::MassShapeSettings(shape, override_mass).Create().Get();
	}

	shape_pool_mutex.lock();
	auto shape_handle = shape_pool->insert(shape);
	shape_pool_mutex.unlock();
	return shape_handle;
}

Shape shapeCreateCompound(const SubShapeSettings sub_shapes[], size_t sub_shape_count, UserData user_data) {
	auto static_shape_settings = JPH::StaticCompoundShapeSettings();
	static_shape_settings.mUserData = user_data;

	shape_pool_mutex.lock();
	for (auto i = 0; i < sub_shape_count; i++) {
		auto subshape = &sub_shapes[i];
		auto shape_ref = shape_pool->get(subshape->shape);
		static_shape_settings.AddShape(loadVec3(subshape->position), loadQuat(subshape->rotation), shape_ref, i);
	}

	auto shape = static_shape_settings.Create().Get();
	auto shape_handle = shape_pool->insert(shape);
	shape_pool_mutex.unlock();
	return shape_handle;
}

void shapeDestroy(Shape shape) {
	shape_pool_mutex.lock();
	shape_pool->remove(shape);
	shape_pool_mutex.unlock();
}

MassProperties shapeGetMassProperties(Shape shape) {
	shape_pool_mutex.lock();
	auto shape_ref = shape_pool->get(shape);
	shape_pool_mutex.unlock();
	auto shape_properties = shape_ref->GetMassProperties();
	MassProperties mass_properties;
	mass_properties.mass = shape_properties.mMass;
	shape_properties.mInertia.StoreFloat4x4(reinterpret_cast<JPH::Float4 *>(mass_properties.inertia_tensor));
	return mass_properties;
}

World *worldCreate(const WorldSettings *settings) {
	return new World(settings);
}

void worldDestroy(World *world_ptr) {
	delete world_ptr;
}

void worldUpdate(World *world_ptr, float delta_time, int collision_steps) {
	world_ptr->update(delta_time, collision_steps);
}

void worldAddBody(World *world_ptr, Body *body_ptr) {
	world_ptr->addBody(body_ptr);
}

void worldRemoveBody(World *world_ptr, Body *body_ptr) {
	world_ptr->removeBody(body_ptr);
}

bool worldCastRayCloset(World *world_ptr, ObjectLayer object_layer_pattern, const RVec3 origin, const Vec3 direction, RayCastHit *hit_result) {
	return world_ptr->castRayCloset(object_layer_pattern, loadRVec3(origin), loadVec3(direction), hit_result);
}

bool worldCastRayClosetIgnoreBody(World *world_ptr, ObjectLayer object_layer_pattern, Body *ignore_body_ptr, const RVec3 origin, const Vec3 direction, RayCastHit *hit_result) {
	JPH::BodyID ignore_body_id;

	if (ignore_body_ptr != nullptr && ignore_body_ptr->world_ptr == world_ptr) {
		ignore_body_id = ignore_body_ptr->body_id;
	}

	return world_ptr->castRayClosetIgnoreBody(object_layer_pattern, ignore_body_id, loadRVec3(origin), loadVec3(direction), hit_result);
}

void worldCastShape(World *world_ptr, ObjectLayer object_layer_pattern, Shape shape, const Transform *c_transform, ShapeCastCallback callback, void *callback_data) {
	shape_pool_mutex.lock();
	auto shape_ref = shape_pool->get(shape);
	shape_pool_mutex.unlock();
	world_ptr->castShape(object_layer_pattern, loadRVec3(c_transform->position), loadQuat(c_transform->rotation), shape_ref, callback, callback_data);
}

// Body functions
Body *bodyCreate(const BodySettings *settings) {
	return new Body(settings);
}

void bodyDestroy(Body *body_ptr) {
	delete body_ptr;
}

World *bodyGetWorld(Body *body_ptr) {
	return body_ptr->getWorld();
}

Transform bodyGetTransform(Body *body_ptr) {
	auto position = body_ptr->getPosition();
	auto rotation = body_ptr->getRotation();
	return Transform{
		{position.GetX(), position.GetY(), position.GetZ()},
		{rotation.GetX(), rotation.GetY(), rotation.GetZ(), rotation.GetW()}};
}

void bodySetTransform(Body *body_ptr, const Transform *c_transform) {
	body_ptr->setTransform(loadRVec3(c_transform->position), loadQuat(c_transform->rotation));
}

Velocity bodyGetVelocity(Body *body_ptr) {
	auto linear = body_ptr->getLinearVelocity();
	auto angular = body_ptr->getAngularVelocity();
	return Velocity{
		{linear.GetX(), linear.GetY(), linear.GetZ()},
		{angular.GetX(), angular.GetY(), angular.GetZ()},

	};
}

void bodySetVelocity(Body *body_ptr, const Velocity *c_velocity) {
	body_ptr->setVelocity(loadVec3(c_velocity->linear), loadVec3(c_velocity->angular));
}

void bodyAddForce(Body *body_ptr, const Vec3 force, bool activate) {
	body_ptr->addForce(loadVec3(force), activate ? JPH::EActivation::Activate : JPH::EActivation::DontActivate);
}

void bodyAddTorque(Body *body_ptr, const Vec3 torque, bool activate) {
	body_ptr->addTorque(loadVec3(torque), activate ? JPH::EActivation::Activate : JPH::EActivation::DontActivate);
}

void bodyAddImpulse(Body *body_ptr, const Vec3 impulse) {
	body_ptr->addImpulse(loadVec3(impulse));
}

void bodyAddAngularImpulse(Body *body_ptr, const Vec3 angular_impulse) {
	body_ptr->addAngularImpulse(loadVec3(angular_impulse));
}

SubShapeIndex bodyAddShape(Body *body_ptr, Shape shape, const Vec3 position, const Quat rotation, UserData user_data) {
	shape_pool_mutex.lock();
	auto shape_ref = shape_pool->get(shape);
	shape_pool_mutex.unlock();

	return body_ptr->addShape(SubShape{
		shape_ref,
		loadVec3(position),
		loadQuat(rotation),
		user_data,
	});
}

void bodyRemoveShape(Body *body_ptr, SubShapeIndex index) {
	body_ptr->removeShape(index);
}

void bodyUpdateShapeTransform(Body *body_ptr, SubShapeIndex index, const Vec3 position, const Quat rotation) {
	body_ptr->updateShapeTransform(index, loadVec3(position), loadQuat(rotation));
}

void bodyRemoveAllShapes(Body *body_ptr) {
	body_ptr->removeAllShape();
}

void bodyCommitShapeChanges(Body *body_ptr) {
	body_ptr->commitShapeChanges();
}
