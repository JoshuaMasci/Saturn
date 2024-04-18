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
    exe.addIncludePath(std.Build.LazyPath.relative("libs"));

    // Opengl
    exe.addIncludePath(std.Build.LazyPath.relative("libs/glad/include"));
    exe.addCSourceFile(.{ .file = std.Build.LazyPath.relative("libs/glad/src/glad.c"), .flags = &[_][]const u8{"-std=c99"} });

    const zmath = b.dependency("zmath", .{ .enable_cross_platform_determinism = true });
    exe.root_module.addImport("zmath", zmath.module("root"));

    //SDL3
    exe.linkSystemLibrary("sdl3");

    //cimgui
    const cimgui = try build_cimgui(b, target, optimize);
    exe.linkLibrary(cimgui);

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

fn build_cimgui(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    var lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    lib.linkLibC();
    lib.linkLibCpp();

    lib.addIncludePath(.{ .path = "libs" });

    const CIMGUI_PATH = "libs/cimgui/";

    const C_FLAGS = &.{};

    lib.addCSourceFiles(.{
        .files = &.{
            CIMGUI_PATH ++ "cimgui.cpp",
        },
        .flags = C_FLAGS,
    });

    const IMGUI_PATH = "libs/cimgui/imgui/";

    lib.addCSourceFiles(.{
        .files = &.{
            IMGUI_PATH ++ "imgui.cpp",
            IMGUI_PATH ++ "imgui_widgets.cpp",
            IMGUI_PATH ++ "imgui_tables.cpp",
            IMGUI_PATH ++ "imgui_draw.cpp",
            IMGUI_PATH ++ "imgui_demo.cpp",
        },
        .flags = C_FLAGS,
    });

    return lib;
}
