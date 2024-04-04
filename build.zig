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

    exe.addIncludePath(std.Build.LazyPath.relative("glad/include"));
    exe.addCSourceFile(.{ .file = std.Build.LazyPath.relative("glad/src/glad.c"), .flags = &[_][]const u8{"-std=c99"} });

    const zmath = b.dependency("zmath", .{ .enable_cross_platform_determinism = true });
    exe.root_module.addImport("zmath", zmath.module("root"));

    const zsdl = b.dependency("zsdl", .{});
    exe.root_module.addImport("zsdl2", zsdl.module("zsdl2"));

    const zsdl_path = zsdl.path("").getPath(b);
    try @import("zsdl").addLibraryPathsTo(exe, zsdl_path);
    @import("zsdl").link_SDL2(exe);
    try @import("zsdl").install_sdl2(&exe.step, target.result, .bin, zsdl_path);

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
