const std = @import("std");

const Options = struct {
    use_double_precision: bool,
    enable_asserts: bool,
    enable_cross_platform_determinism: bool,
    enable_debug_renderer: bool,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options: Options = .{
        .use_double_precision = b.option(
            bool,
            "use_double_precision",
            "Enable double precision",
        ) orelse false,
        .enable_asserts = b.option(
            bool,
            "enable_asserts",
            "Enable assertions",
        ) orelse (optimize == .Debug),
        .enable_cross_platform_determinism = b.option(
            bool,
            "enable_cross_platform_determinism",
            "Enables cross-platform determinism",
        ) orelse true,
        .enable_debug_renderer = b.option(
            bool,
            "enable_debug_renderer",
            "Enable debug renderer",
        ) orelse false,
    };

    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    const zig_module = b.addModule("root", .{
        .root_source_file = b.path("src/saturn_jolt.zig"),
        .imports = &.{.{ .name = "options", .module = options_module }},
    });
    zig_module.addIncludePath(b.path("src/"));

    const saturn_physics_lib = build_cpp_lib(b, target, optimize, options);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/saturn_jolt.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const lib = b.step("lib", "build cpp static lib");
    lib.dependOn(&saturn_physics_lib.step);
}

fn build_cpp_lib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, options: Options) *std.Build.Step.Compile {
    const library = b.addStaticLibrary(.{
        .name = "saturn_jolt",
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(library);

    //JPH_DEBUG_RENDERER

    library.linkLibC();
    library.linkLibCpp();

    library.addIncludePath(b.path("src/"));

    const jolt_path = "JoltPhysics";
    library.addIncludePath(b.path(jolt_path));

    const jolt_src_path = jolt_path ++ "/Jolt/";



    const c_flags: []const []const u8 = &.{
        "-std=c++17",
        "-fno-access-control",
        "-fno-sanitize=undefined",
        if (options.use_double_precision) "-DJPH_DOUBLE_PRECISION" else "",
        if (options.enable_asserts) "-DJPH_ENABLE_ASSERTS" else "",
        if (options.enable_cross_platform_determinism) "-DJPH_CROSS_PLATFORM_DETERMINISTIC" else "",
        if (options.enable_debug_renderer) "-DJPH_DEBUG_RENDERER" else "",
    };

    library.addCSourceFiles(.{
        .files = &.{
            "src/saturn_jolt.cpp",
            "src/world.cpp",
            "src/body.cpp",
            "src/mass_shape.cpp",
        },
        .flags = c_flags,
    });

    if (options.enable_debug_renderer) {
        library.addCSourceFile(.{
            .file = b.path("src/callback_debug_renderer.cpp"),
            .flags = c_flags,
        });
    }

    // File list generated via following command, will probably need to rerun when updating
    // find ./Jolt -name "*.cpp" | sed 's|./Jolt/|jolt_src_path ++ "|' | sed 's|$|",|'
    library.addCSourceFiles(.{ .files = &.{
        jolt_src_path ++ "Core/TickCounter.cpp",
        jolt_src_path ++ "Core/Factory.cpp",
        jolt_src_path ++ "Core/Memory.cpp",
        jolt_src_path ++ "Core/JobSystemThreadPool.cpp",
        jolt_src_path ++ "Core/StringTools.cpp",
        jolt_src_path ++ "Core/JobSystemSingleThreaded.cpp",
        jolt_src_path ++ "Core/Color.cpp",
        jolt_src_path ++ "Core/IssueReporting.cpp",
        jolt_src_path ++ "Core/LinearCurve.cpp",
        jolt_src_path ++ "Core/JobSystemWithBarrier.cpp",
        jolt_src_path ++ "Core/Profiler.cpp",
        jolt_src_path ++ "Core/RTTI.cpp",
        jolt_src_path ++ "Core/Semaphore.cpp",
        jolt_src_path ++ "ObjectStream/ObjectStreamIn.cpp",
        jolt_src_path ++ "ObjectStream/ObjectStreamBinaryOut.cpp",
        jolt_src_path ++ "ObjectStream/ObjectStreamTextOut.cpp",
        jolt_src_path ++ "ObjectStream/TypeDeclarations.cpp",
        jolt_src_path ++ "ObjectStream/ObjectStream.cpp",
        jolt_src_path ++ "ObjectStream/ObjectStreamOut.cpp",
        jolt_src_path ++ "ObjectStream/ObjectStreamBinaryIn.cpp",
        jolt_src_path ++ "ObjectStream/SerializableObject.cpp",
        jolt_src_path ++ "ObjectStream/ObjectStreamTextIn.cpp",
        jolt_src_path ++ "Skeleton/SkeletonPose.cpp",
        jolt_src_path ++ "Skeleton/SkeletalAnimation.cpp",
        jolt_src_path ++ "Skeleton/Skeleton.cpp",
        jolt_src_path ++ "Skeleton/SkeletonMapper.cpp",
        jolt_src_path ++ "AABBTree/AABBTreeBuilder.cpp",
        jolt_src_path ++ "RegisterTypes.cpp",
        jolt_src_path ++ "Renderer/DebugRenderer.cpp",
        jolt_src_path ++ "Renderer/DebugRendererPlayback.cpp",
        jolt_src_path ++ "Renderer/DebugRendererRecorder.cpp",
        jolt_src_path ++ "Renderer/DebugRendererSimple.cpp",
        jolt_src_path ++ "Physics/SoftBody/SoftBodySharedSettings.cpp",
        jolt_src_path ++ "Physics/SoftBody/SoftBodyShape.cpp",
        jolt_src_path ++ "Physics/SoftBody/SoftBodyMotionProperties.cpp",
        jolt_src_path ++ "Physics/SoftBody/SoftBodyCreationSettings.cpp",
        jolt_src_path ++ "Physics/Vehicle/VehicleController.cpp",
        jolt_src_path ++ "Physics/Vehicle/VehicleTransmission.cpp",
        jolt_src_path ++ "Physics/Vehicle/VehicleEngine.cpp",
        jolt_src_path ++ "Physics/Vehicle/Wheel.cpp",
        jolt_src_path ++ "Physics/Vehicle/WheeledVehicleController.cpp",
        jolt_src_path ++ "Physics/Vehicle/MotorcycleController.cpp",
        jolt_src_path ++ "Physics/Vehicle/VehicleAntiRollBar.cpp",
        jolt_src_path ++ "Physics/Vehicle/VehicleTrack.cpp",
        jolt_src_path ++ "Physics/Vehicle/TrackedVehicleController.cpp",
        jolt_src_path ++ "Physics/Vehicle/VehicleDifferential.cpp",
        jolt_src_path ++ "Physics/Vehicle/VehicleCollisionTester.cpp",
        jolt_src_path ++ "Physics/Vehicle/VehicleConstraint.cpp",
        jolt_src_path ++ "Physics/PhysicsUpdateContext.cpp",
        jolt_src_path ++ "Physics/Ragdoll/Ragdoll.cpp",
        jolt_src_path ++ "Physics/DeterminismLog.cpp",
        jolt_src_path ++ "Physics/PhysicsSystem.cpp",
        jolt_src_path ++ "Physics/Body/BodyManager.cpp",
        jolt_src_path ++ "Physics/Body/Body.cpp",
        jolt_src_path ++ "Physics/Body/BodyInterface.cpp",
        jolt_src_path ++ "Physics/Body/MotionProperties.cpp",
        jolt_src_path ++ "Physics/Body/MassProperties.cpp",
        jolt_src_path ++ "Physics/Body/BodyCreationSettings.cpp",
        jolt_src_path ++ "Physics/LargeIslandSplitter.cpp",
        jolt_src_path ++ "Physics/Constraints/Constraint.cpp",
        jolt_src_path ++ "Physics/Constraints/PulleyConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/DistanceConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/TwoBodyConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/GearConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/SixDOFConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/PathConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/PathConstraintPath.cpp",
        jolt_src_path ++ "Physics/Constraints/ConeConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/MotorSettings.cpp",
        jolt_src_path ++ "Physics/Constraints/SliderConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/SpringSettings.cpp",
        jolt_src_path ++ "Physics/Constraints/ContactConstraintManager.cpp",
        jolt_src_path ++ "Physics/Constraints/FixedConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/ConstraintManager.cpp",
        jolt_src_path ++ "Physics/Constraints/SwingTwistConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/HingeConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/RackAndPinionConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/PointConstraint.cpp",
        jolt_src_path ++ "Physics/Constraints/PathConstraintPathHermite.cpp",
        jolt_src_path ++ "Physics/Character/CharacterVirtual.cpp",
        jolt_src_path ++ "Physics/Character/CharacterBase.cpp",
        jolt_src_path ++ "Physics/Character/Character.cpp",
        jolt_src_path ++ "Physics/IslandBuilder.cpp",
        jolt_src_path ++ "Physics/PhysicsScene.cpp",
        jolt_src_path ++ "Physics/StateRecorderImpl.cpp",
        jolt_src_path ++ "Physics/Collision/TransformedShape.cpp",
        jolt_src_path ++ "Physics/Collision/CastConvexVsTriangles.cpp",
        jolt_src_path ++ "Physics/Collision/CollisionGroup.cpp",
        jolt_src_path ++ "Physics/Collision/CollideSphereVsTriangles.cpp",
        jolt_src_path ++ "Physics/Collision/ManifoldBetweenTwoFaces.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/OffsetCenterOfMassShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/RotatedTranslatedShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/ConvexShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/BoxShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/MeshShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/TaperedCylinderShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/ConvexHullShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/ScaledShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/CompoundShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/CapsuleShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/TaperedCapsuleShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/EmptyShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/DecoratedShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/Shape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/PlaneShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/CylinderShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/SphereShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/StaticCompoundShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/HeightFieldShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/MutableCompoundShape.cpp",
        jolt_src_path ++ "Physics/Collision/Shape/TriangleShape.cpp",
        jolt_src_path ++ "Physics/Collision/CollideConvexVsTriangles.cpp",
        jolt_src_path ++ "Physics/Collision/EstimateCollisionResponse.cpp",
        jolt_src_path ++ "Physics/Collision/PhysicsMaterial.cpp",
        jolt_src_path ++ "Physics/Collision/BroadPhase/BroadPhaseBruteForce.cpp",
        jolt_src_path ++ "Physics/Collision/BroadPhase/BroadPhase.cpp",
        jolt_src_path ++ "Physics/Collision/BroadPhase/BroadPhaseQuadTree.cpp",
        jolt_src_path ++ "Physics/Collision/BroadPhase/QuadTree.cpp",
        jolt_src_path ++ "Physics/Collision/NarrowPhaseStats.cpp",
        jolt_src_path ++ "Physics/Collision/GroupFilter.cpp",
        jolt_src_path ++ "Physics/Collision/CastSphereVsTriangles.cpp",
        jolt_src_path ++ "Physics/Collision/PhysicsMaterialSimple.cpp",
        jolt_src_path ++ "Physics/Collision/GroupFilterTable.cpp",
        jolt_src_path ++ "Physics/Collision/CollisionDispatch.cpp",
        jolt_src_path ++ "Physics/Collision/NarrowPhaseQuery.cpp",
        jolt_src_path ++ "Math/Vec3.cpp",
        jolt_src_path ++ "Geometry/Indexify.cpp",
        jolt_src_path ++ "Geometry/OrientedBox.cpp",
        jolt_src_path ++ "Geometry/ConvexHullBuilder.cpp",
        jolt_src_path ++ "Geometry/ConvexHullBuilder2D.cpp",
        jolt_src_path ++ "TriangleSplitter/TriangleSplitterMean.cpp",
        jolt_src_path ++ "TriangleSplitter/TriangleSplitter.cpp",
        jolt_src_path ++ "TriangleSplitter/TriangleSplitterBinning.cpp",
    }, .flags = c_flags });

    return library;
}
