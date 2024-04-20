const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Saturn",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.addIncludePath(std.Build.path(b, "libs"));

    // Opengl
    exe.addIncludePath(std.Build.path(b, "libs/glad/include"));
    exe.addCSourceFile(.{ .file = std.Build.path(b, "libs/glad/src/glad.c"), .flags = &[_][]const u8{"-std=c99"} });

    // SDL3
    exe.linkSystemLibrary("sdl3");

    // zMath
    const zmath = b.dependency("zmath", .{ .enable_cross_platform_determinism = true });
    exe.root_module.addImport("zmath", zmath.module("root"));

    // zImgui
    const zgui = b.dependency("zgui", .{
        .shared = false,
        .with_implot = false,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

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
