const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dxc_module = b.addModule("dxc", .{
        .root_source_file = b.path("src/dxc.zig"),
        .target = target,
        .optimize = optimize,
    });

    dxc_module.addCSourceFile(.{
        .file = b.path("src/dxc_wrapper.cpp"),
        .flags = &.{
            "-std=c++17",
            "-fno-exceptions",
            "-fno-rtti",
            "-fms-extensions",
        },
    });

    dxc_module.linkSystemLibrary("dxcompiler", .{});
    dxc_module.link_libcpp = true;

    const example = b.addExecutable(.{
        .name = "dxc-example",
        .root_source_file = b.path("examples/example.zig"),
        .target = target,
        .optimize = optimize,
    });

    example.root_module.addImport("dxc", dxc_module);
    b.installArtifact(example);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/dxc.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.addCSourceFile(.{
        .file = b.path("src/dxc_wrapper.cpp"),
        .flags = &.{
            "-std=c++17",
            "-fno-exceptions",
            "-fno-rtti",
            "-fms-extensions",
        },
    });
    tests.linkSystemLibrary("dxcompiler");
    tests.linkLibCpp();

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // Run example
    const run_example = b.addRunArtifact(example);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_example.step);
}
