const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    var option_step = b.addOptions();

    const build_sdl3 = b.option(bool, "build_sdl3", "build and link sdl3 from source instead") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "saturn",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("saturn_options", option_step.createModule());

    if (build_sdl3) {
        const sdl3 = b.dependency("sdl3", .{
            .target = target,
            .optimize = optimize,
            .preferred_link_mode = .dynamic,
        });
        exe.linkLibrary(sdl3.artifact("SDL3"));
    } else {
        exe.linkSystemLibrary("SDL3");
    }

    // dear imgui
    const zimgui = b.dependency("zgui", .{
        .shared = false,
        .backend = .sdl3_gpu,
        .with_gizmo = true,
    });
    exe.root_module.addImport("zimgui", zimgui.module("root"));
    exe.linkLibrary(zimgui.artifact("imgui"));

    // zstbi
    const zstbi = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi.module("root"));

    // saturn physics abstraction
    const saturn_jolt = b.dependency("saturn_jolt", .{ .enable_debug_renderer = true });
    exe.root_module.addImport("physics", saturn_jolt.module("root"));

    // zmath
    const zmath = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath.module("root"));

    // zgltf
    const zgltf = b.dependency("zgltf", .{});
    exe.root_module.addImport("zgltf", zgltf.module("zgltf"));

    // zobj
    const zobj = b.dependency("zobj", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zobj", zobj.module("obj"));

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

        if (build_sdl3) {
            const sdl3 = b.dependency("sdl3", .{
                .target = target,
                .optimize = optimize,
                .preferred_link_mode = .dynamic,
            });
            assets_exe.linkLibrary(sdl3.artifact("SDL3"));
        } else {
            assets_exe.linkSystemLibrary("SDL3");
        }

        //TODO: link included versions, rather than system libs
        assets_exe.linkSystemLibrary("SDL3_shadercross");
        assets_exe.linkSystemLibrary("spirv-cross-c-shared");
        assets_exe.linkSystemLibrary("dxcompiler");

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
