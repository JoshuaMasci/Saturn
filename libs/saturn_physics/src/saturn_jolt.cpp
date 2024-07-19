#include "saturn_jolt.h"

#include <iostream>

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Math/Real.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/MutableCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>

#include "generational_pool.hpp"

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

typedef GenerationalPool<JPH::Ref<JPH::Shape>> ShapePool;
ShapePool *shape_pool = NULL;

void SPH_Init(const SPH_AllocationFunctions *functions)
{
    if (functions != NULL)
    {
        JPH::Allocate = functions->alloc;
        JPH::Free = functions->free;
        JPH::AlignedAllocate = functions->aligned_alloc;
        JPH::AlignedFree = functions->aligned_free;
    }
    else
    {
        JPH::RegisterDefaultAllocator();
    }

    auto factory = static_cast<JPH::Factory *>(JPH::Allocate(sizeof(JPH::Factory)));
    ::new (factory) JPH::Factory();
    JPH::Factory::sInstance = factory;
    JPH::RegisterTypes();

    shape_pool = alloc_t<ShapePool>();
    ::new (shape_pool) ShapePool();
}

void SPH_Deinit()
{
    shape_pool->~ShapePool();
    free_t(shape_pool);

    JPH::UnregisterTypes();
    JPH::Factory::sInstance->~Factory();
    JPH::Free((void *)JPH::Factory::sInstance);
    JPH::Factory::sInstance = nullptr;

    JPH::Allocate = NULL;
    JPH::Free = NULL;
    JPH::AlignedAllocate = NULL;
    JPH::AlignedFree = NULL;
}

SPH_ShapeHandle SPH_Shape_Sphere(float radius, float density)
{
    auto settings = JPH::SphereShapeSettings();
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->add(shape).to_u64();
}
SPH_ShapeHandle SPH_Shape_Box(const float half_extent[3], float density)
{
    auto settings = JPH::BoxShapeSettings();
    settings.mHalfExtent = JPH::Vec3(*reinterpret_cast<const JPH::Float3 *>(half_extent));
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->add(shape).to_u64();
}
SPH_ShapeHandle SPH_Shape_Cylinder(float half_height, float radius, float density)
{
    auto settings = JPH::CylinderShapeSettings();
    settings.mHalfHeight = half_height;
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->add(shape).to_u64();
}
SPH_ShapeHandle SPH_Shape_Capsule(float half_height, float radius, float density)
{
    auto settings = JPH::CapsuleShapeSettings();
    settings.mHalfHeightOfCylinder = half_height;
    settings.mRadius = radius;
    settings.mDensity = density;
    auto shape = settings.Create().Get();
    return shape_pool->add(shape).to_u64();
}
void SPH_Shape_Destroy(SPH_ShapeHandle handle)
{
    shape_pool->remove(ShapePool::Handle::from_u64(handle));
}

namespace Layers
{
    static constexpr JPH::ObjectLayer NON_MOVING = 0;
    static constexpr JPH::ObjectLayer MOVING = 1;
    static constexpr JPH::ObjectLayer NUM_LAYERS = 2;
};

/// Class that determines if two object layers can collide
class ObjectLayerPairFilterImpl : public JPH::ObjectLayerPairFilter
{
public:
    virtual bool ShouldCollide(JPH::ObjectLayer inObject1, JPH::ObjectLayer inObject2) const override
    {
        switch (inObject1)
        {
        case Layers::NON_MOVING:
            return inObject2 == Layers::MOVING; // Non moving only collides with moving
        case Layers::MOVING:
            return true; // Moving collides with everything
        default:
            JPH_ASSERT(false);
            return false;
        }
    }
};

namespace BroadPhaseLayers
{
    static constexpr JPH::BroadPhaseLayer NON_MOVING(0);
    static constexpr JPH::BroadPhaseLayer MOVING(1);
    static constexpr uint NUM_LAYERS(2);
};

// BroadPhaseLayerInterface implementation
// This defines a mapping between object and broadphase layers.
class BPLayerInterfaceImpl final : public JPH::BroadPhaseLayerInterface
{
public:
    BPLayerInterfaceImpl()
    {
        // Create a mapping table from object to broad phase layer
        mObjectToBroadPhase[Layers::NON_MOVING] = BroadPhaseLayers::NON_MOVING;
        mObjectToBroadPhase[Layers::MOVING] = BroadPhaseLayers::MOVING;
    }

    virtual uint GetNumBroadPhaseLayers() const override
    {
        return BroadPhaseLayers::NUM_LAYERS;
    }

    virtual JPH::BroadPhaseLayer GetBroadPhaseLayer(JPH::ObjectLayer inLayer) const override
    {
        JPH_ASSERT(inLayer < Layers::NUM_LAYERS);
        return mObjectToBroadPhase[inLayer];
    }

#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
    virtual const char *GetBroadPhaseLayerName(BroadPhaseLayer inLayer) const override
    {
        switch ((BroadPhaseLayer::Type)inLayer)
        {
        case (BroadPhaseLayer::Type)BroadPhaseLayers::NON_MOVING:
            return "NON_MOVING";
        case (BroadPhaseLayer::Type)BroadPhaseLayers::MOVING:
            return "MOVING";
        default:
            JPH_ASSERT(false);
            return "INVALID";
        }
    }
#endif // JPH_EXTERNAL_PROFILE || JPH_PROFILE_ENABLED

private:
    JPH::BroadPhaseLayer mObjectToBroadPhase[Layers::NUM_LAYERS];
};

/// Class that determines if an object layer can collide with a broadphase layer
class ObjectVsBroadPhaseLayerFilterImpl : public JPH::ObjectVsBroadPhaseLayerFilter
{
public:
    virtual bool ShouldCollide(JPH::ObjectLayer inLayer1, JPH::BroadPhaseLayer inLayer2) const override
    {
        switch (inLayer1)
        {
        case Layers::NON_MOVING:
            return inLayer2 == BroadPhaseLayers::MOVING;
        case Layers::MOVING:
            return true;
        default:
            JPH_ASSERT(false);
            return false;
        }
    }
};

// An example contact listener
class MyContactListener : public JPH::ContactListener
{
public:
    // See: ContactListener
    virtual JPH::ValidateResult OnContactValidate(const JPH::Body &inBody1, const JPH::Body &inBody2, JPH::RVec3Arg inBaseOffset, const JPH::CollideShapeResult &inCollisionResult) override
    {
        std::cout << "Contact validate callback" << std::endl;
        // Allows you to ignore a contact before it is created (using layers to not make objects collide is cheaper!)
        return JPH::ValidateResult::AcceptAllContactsForThisBodyPair;
    }

    virtual void OnContactAdded(const JPH::Body &inBody1, const JPH::Body &inBody2, const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) override
    {
        std::cout << "A contact was added" << std::endl;
    }

    virtual void OnContactPersisted(const JPH::Body &inBody1, const JPH::Body &inBody2, const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) override
    {
        std::cout << "A contact was persisted" << std::endl;
    }

    virtual void OnContactRemoved(const JPH::SubShapeIDPair &inSubShapePair) override
    {
        std::cout << "A contact was removed" << std::endl;
    }
};

class PhysicsWorld
{
public:
    PhysicsWorld(const SPH_PhysicsWorldSettings *settings)
        : temp_allocator(settings->temp_allocation_size), job_system(1024)
    {
        this->broad_phase_layer_interface = alloc_t<BPLayerInterfaceImpl>();
        ::new (this->broad_phase_layer_interface) BPLayerInterfaceImpl();

        this->object_vs_broadphase_layer_filter = alloc_t<ObjectVsBroadPhaseLayerFilterImpl>();
        ::new (this->object_vs_broadphase_layer_filter) ObjectVsBroadPhaseLayerFilterImpl();

        this->object_vs_object_layer_filter = alloc_t<ObjectLayerPairFilterImpl>();
        ::new (this->object_vs_object_layer_filter) ObjectLayerPairFilterImpl();

        this->physics_system = alloc_t<JPH::PhysicsSystem>();
        ::new (this->physics_system) JPH::PhysicsSystem();
        this->physics_system->Init(settings->max_bodies, settings->num_body_mutexes, settings->max_body_pairs, settings->max_contact_constraints, *this->broad_phase_layer_interface, *this->object_vs_broadphase_layer_filter, *this->object_vs_object_layer_filter);
        this->physics_system->SetGravity(JPH::Vec3(0.0, -9.8, 0.0));
    }

    ~PhysicsWorld()
    {
        this->physics_system->~PhysicsSystem();
        free_t(this->physics_system);

        this->broad_phase_layer_interface->~BPLayerInterfaceImpl();
        free_t(this->broad_phase_layer_interface);

        this->object_vs_broadphase_layer_filter->~ObjectVsBroadPhaseLayerFilterImpl();
        free_t(this->object_vs_broadphase_layer_filter);

        this->object_vs_object_layer_filter->~ObjectLayerPairFilterImpl();
        free_t(this->object_vs_object_layer_filter);
    }

public:
    BPLayerInterfaceImpl *broad_phase_layer_interface;
    ObjectVsBroadPhaseLayerFilterImpl *object_vs_broadphase_layer_filter;
    ObjectLayerPairFilterImpl *object_vs_object_layer_filter;
    JPH::PhysicsSystem *physics_system;

    JPH::TempAllocatorImpl temp_allocator;
    JPH::JobSystemSingleThreaded job_system;
};

SPH_PhysicsWorld *SPH_PhysicsWorld_Create(const SPH_PhysicsWorldSettings *settings)
{
    auto physics_world = alloc_t<PhysicsWorld>();
    ::new (physics_world) PhysicsWorld(settings);
    return (SPH_PhysicsWorld *)physics_world;
}

void SPH_PhysicsWorld_Destroy(SPH_PhysicsWorld *ptr)
{
    auto physics_world = (PhysicsWorld *)ptr;
    physics_world->~PhysicsWorld();
    free_t(physics_world);
}

void SPH_PhysicsWorld_Update(SPH_PhysicsWorld *ptr, float inDeltaTime, int inCollisionSteps)
{
    auto physics_world = (PhysicsWorld *)ptr;
    physics_world->physics_system->Update(inDeltaTime, inCollisionSteps, &physics_world->temp_allocator, &physics_world->job_system);
}

SPH_BodyHandle SPH_PhysicsWorld_Body_Create(SPH_PhysicsWorld *ptr, const SPH_BodySettings *body_settings)
{
    auto physics_world = (PhysicsWorld *)ptr;
    auto shape = shape_pool->get(ShapePool::Handle::from_u64(body_settings->shape));
    auto position = JPH::Vec3(*reinterpret_cast<const JPH::Float3 *>(body_settings->position));
    auto rotation = JPH::Quat(body_settings->rotation[0], body_settings->rotation[1], body_settings->rotation[2], body_settings->rotation[3]);
    auto linear_velocity = JPH::Vec3(*reinterpret_cast<const JPH::Float3 *>(body_settings->linear_velocity));
    auto angular_velocity = JPH::Vec3(*reinterpret_cast<const JPH::Float3 *>(body_settings->angular_velocity));
    auto settings = JPH::BodyCreationSettings();
    settings.SetShape(shape);
    settings.mPosition = position;
    settings.mRotation = rotation;
    settings.mLinearVelocity = linear_velocity;
    settings.mAngularVelocity = angular_velocity;
    settings.mUserData = body_settings->user_data;

    switch (body_settings->motion_type)
    {
    case 0:
        settings.mMotionType = JPH::EMotionType::Static;
        break;
    case 1:
        settings.mMotionType = JPH::EMotionType::Kinematic;
        break;
    case 2:
        settings.mMotionType = JPH::EMotionType::Dynamic;
        break;
    }

    settings.mIsSensor = body_settings->is_sensor;
    settings.mAllowSleeping = body_settings->allow_sleep;
    settings.mFriction = body_settings->friction;
    settings.mGravityFactor = body_settings->gravity_factor;

    JPH::BodyInterface &body_interface = physics_world->physics_system->GetBodyInterface();
    JPH::BodyID body_id = body_interface.CreateAndAddBody(settings, JPH::EActivation::Activate);
    return body_id.GetIndexAndSequenceNumber();
}

void SPH_PhysicsWorld_Body_Destroy(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle)
{
    auto physics_world = (PhysicsWorld *)ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface = physics_world->physics_system->GetBodyInterface();
    body_interface.RemoveBody(body_id);
    body_interface.DestroyBody(body_id);
}

SPH_Transform SPH_PhysicsWorld_Body_GetTransform(SPH_PhysicsWorld *ptr, SPH_BodyHandle handle)
{
    auto physics_world = (PhysicsWorld *)ptr;
    auto body_id = JPH::BodyID(handle);
    JPH::BodyInterface &body_interface = physics_world->physics_system->GetBodyInterface();
    JPH::RVec3 position;
    JPH::Quat rotation;
    body_interface.GetPositionAndRotation(body_id, position, rotation);
    // auto position = body_interface.GetPosition(body_id);
    // auto rotation = body_interface.GetRotation(body_id);

    return SPH_Transform{
        {position.GetX(), position.GetY(), position.GetZ()},
        {rotation.GetX(), rotation.GetY(), rotation.GetZ(), rotation.GetW()}};
}