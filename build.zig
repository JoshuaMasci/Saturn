const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const use_sdl3 = b.option(bool, "use_sdl3", "use sdl3 instead of sdl2") orelse false;
    var option_step = b.addOptions();
    option_step.addOption(bool, "sdl3", use_sdl3);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "saturn",
        .root_source_file = b.path("src/main.zig"),
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

    // zobj
    const zobj = b.dependency("zobj", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zobj", zobj.module("obj"));

    if (!use_sdl3) { // zsdl
        const zsdl = b.dependency("zsdl", .{});
        exe.root_module.addImport("zsdl2", zsdl.module("zsdl2"));
        @import("zsdl").link_SDL2(exe);

        // zopengl
        const zopengl = b.dependency("zopengl", .{});
        exe.root_module.addImport("zopengl", zopengl.module("root"));
    } else {
        const sdl3 = b.dependency("sdl3", .{
            .target = target,
            .optimize = optimize,
            .preferred_link_mode = .dynamic,
        });
        exe.linkLibrary(sdl3.artifact("SDL3"));
    }

    // zstbi
    const zstbi = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    // saturn physics abstraction
    const saturn_jolt = b.dependency("saturn_jolt", .{});
    exe.root_module.addImport("physics", saturn_jolt.module("root"));
    exe.linkLibrary(saturn_jolt.artifact("saturn_jolt"));

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Asset processing exe
    {
        const assets_exe = b.addExecutable(.{
            .name = "saturn_assets",
            .root_source_file = b.path("src/asset_main.zig"),
            .target = target,
            .optimize = optimize,
        });

        assets_exe.root_module.addImport("zobj", zobj.module("obj"));
        assets_exe.root_module.addImport("zstbi", zstbi.module("root"));
        assets_exe.linkLibrary(zstbi.artifact("zstbi"));

        // Always link sdl3 for the asset pipeline I guess?
        // Shader cross needs it, the sdl2 mode will be deprecated anyways
        const sdl3 = b.dependency("sdl3", .{
            .target = target,
            .optimize = optimize,
            .preferred_link_mode = .dynamic,
        });
        assets_exe.linkLibrary(sdl3.artifact("SDL3"));
        assets_exe.linkSystemLibrary("SDL3_shadercross");

        b.installArtifact(assets_exe);
        const run_assets_cmd = b.addRunArtifact(assets_exe);
        run_assets_cmd.step.dependOn(b.getInstallStep());
        run_assets_cmd.addArg("assets/");
        run_assets_cmd.addArg("zig-out/assets"); //TODO: get this path from builder
        const run_assets_step = b.step("assets", "Process assets");
        run_assets_step.dependOn(&run_assets_cmd.step);
    }

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
