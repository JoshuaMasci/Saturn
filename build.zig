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

    // zsdl
    const zsdl = b.dependency("zsdl", .{});
    exe.root_module.addImport("zsdl3", zsdl.module("zsdl3"));
    @import("zsdl").link_SDL3(exe);

    // zopengl
    const zopengl = b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));

    // zimgui
    const zimgui = b.dependency("zimgui", .{
        .backend = .sdl3_opengl3,
    });
    exe.root_module.addImport("zimgui", zimgui.module("root"));
    exe.linkLibrary(zimgui.artifact("imgui"));

    // zmath
    const zmath = b.dependency("zmath", .{ .enable_cross_platform_determinism = true });
    exe.root_module.addImport("zmath", zmath.module("root"));

    // zmesh
    const zmesh = b.dependency("zmesh", .{});
    exe.root_module.addImport("zmesh", zmesh.module("root"));
    exe.linkLibrary(zmesh.artifact("zmesh"));

    // zstbi
    const zstbi = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    // zjolt
    const zjolt = b.dependency("zjolt", .{
        .use_double_precision = false,
        .enable_cross_platform_determinism = true,
    });
    exe.root_module.addImport("zjolt", zjolt.module("root"));
    exe.linkLibrary(zjolt.artifact("joltc"));

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
