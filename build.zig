const std = @import("std");
const builtin = @import("builtin");

const zsdl = @import("libs/zsdl/build.zig");
const zmath = @import("libs/zmath/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Saturn",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();

    exe.addIncludePath(std.build.LazyPath.relative("glad/include"));
    exe.addCSourceFile(.{ .file = std.build.LazyPath.relative("glad/src/glad.c"), .flags = &[_][]const u8{"-std=c99"} });

    const zmath_pkg = zmath.package(b, target, optimize, .{
        .options = .{ .enable_cross_platform_determinism = true },
    });
    const zsdl_pkg = zsdl.package(b, target, optimize, .{});

    zmath_pkg.link(exe);
    zsdl_pkg.link(exe);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
