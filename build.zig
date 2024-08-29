const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const use_sdl3 = b.option(bool, "use_sdl3", "use sdl3 instead of sdl2 (default: no_backend)") orelse false;
    var option_step = b.addOptions();
    option_step.addOption(bool, "sdl3", use_sdl3);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Saturn",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("saturn_options", option_step.createModule());

    // zalgebra
    const zalgebra = b.dependency("zalgebra", .{});
    exe.root_module.addImport("zalgebra", zalgebra.module("zalgebra"));

    // zgltf
    const zgltf = b.dependency("zgltf", .{});
    exe.root_module.addImport("zgltf", zgltf.module("zgltf"));

    // zsdl
    const zsdl = b.dependency("zsdl", .{});
    if (use_sdl3) {
        exe.root_module.addImport("zsdl3", zsdl.module("zsdl3"));
        @import("zsdl").link_SDL3(exe);
    } else {
        exe.root_module.addImport("zsdl2", zsdl.module("zsdl2"));
        @import("zsdl").link_SDL2(exe);
    }

    // zopengl
    const zopengl = b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));

    // zimgui

    const zimgui = if (use_sdl3) b.dependency("zimgui", .{ .backend = .sdl3_opengl3 }) else b.dependency("zimgui", .{ .backend = .sdl2_opengl3 });
    exe.root_module.addImport("zimgui", zimgui.module("root"));
    exe.linkLibrary(zimgui.artifact("imgui"));

    // zmesh
    const zmesh = b.dependency("zmesh", .{});
    exe.root_module.addImport("zmesh", zmesh.module("root"));
    exe.linkLibrary(zmesh.artifact("zmesh"));

    // zstbi
    const zstbi = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    // saturn physics abstraction
    const saturn_physics = b.dependency("saturn_physics", .{});
    exe.root_module.addImport("physics", saturn_physics.module("root"));
    exe.linkLibrary(saturn_physics.artifact("saturn_jolt"));

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
