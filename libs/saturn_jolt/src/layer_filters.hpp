#pragma once

#include <Jolt/Jolt.h>

#include <Jolt/Physics/PhysicsSystem.h>

/// Objects collide if the have a matching high bit
class AnyMatchObjectLayerPairFilter : public JPH::ObjectLayerPairFilter {
public:
    virtual bool ShouldCollide(JPH::ObjectLayer object_layer1, JPH::ObjectLayer object_layer2) const override {
        return (object_layer1 & object_layer2) > 0;
    }
};

class ExactMatchObjectLayerPairFilter : public JPH::ObjectLayerPairFilter {
public:
    virtual bool ShouldCollide(JPH::ObjectLayer object_layer1, JPH::ObjectLayer object_layer2) const override {
        return object_layer1 == object_layer2;
    }
};

/// Object collide if any high bits match the pattern
class AnyMatchObjectLayerFilter : public JPH::ObjectLayerFilter {
public:
    /// Constructor
    explicit AnyMatchObjectLayerFilter(JPH::ObjectLayer pattern)
            : pattern(pattern) {}

    // See ObjectLayerFilter::ShouldCollide
    bool ShouldCollide(JPH::ObjectLayer object_layer1) const override {
        return (this->pattern & object_layer1) > 0;
    }

private:
    JPH::ObjectLayer pattern;
};

/// Object collide if all high bits match the pattern
class ExactMatchObjectLayerFilter : public JPH::ObjectLayerFilter {
public:
    /// Constructor
    explicit ExactMatchObjectLayerFilter(JPH::ObjectLayer pattern)
            : pattern(pattern) {}

    // See ObjectLayerFilter::ShouldCollide
    bool ShouldCollide(JPH::ObjectLayer object_layer1) const override {
        return object_layer1 == this->pattern;
    }

private:
    JPH::ObjectLayer pattern;
};

// BroadPhaseLayerInterface implementation
// This defines a mapping between object and broadphase layers.
class BroadPhaseLayerInterfaceImpl final
        : public JPH::BroadPhaseLayerInterface {
public:
    BroadPhaseLayerInterfaceImpl() {}

    virtual uint GetNumBroadPhaseLayers() const override { return 1; }

    virtual JPH::BroadPhaseLayer
    GetBroadPhaseLayer(JPH::ObjectLayer in_layer) const override {
        return JPH::BroadPhaseLayer(0);
    }
};

/// Class that determines if an object layer can collide with a broadphase layer
class ObjectVsBroadPhaseLayerFilterImpl
        : public JPH::ObjectVsBroadPhaseLayerFilter {
public:
    virtual bool ShouldCollide(JPH::ObjectLayer in_layer1,
                               JPH::BroadPhaseLayer in_layer2) const override {
        return true;
    }
};
