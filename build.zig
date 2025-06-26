const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    var option_step = b.addOptions();

    const build_sdl3 = b.option(bool, "build_sdl3", "Build and link sdl3 from source instead of using systemlib") orelse false;
    const no_assets = b.option(bool, "no_assets", "Don't compile asset pipeline") orelse false;

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
    const zimgui = b.dependency("zimgui", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zimgui", zimgui.module("zimgui"));

    // saturn physics abstraction
    const saturn_jolt = b.dependency("saturn_jolt", .{ .enable_debug_renderer = true });
    exe.root_module.addImport("physics", saturn_jolt.module("root"));

    // zmath
    const zmath = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath.module("root"));

    // zstbi
    const zstbi = b.dependency("zstbi", .{});
    exe.root_module.addImport("zstbi", zstbi.module("root"));

    // zgltf
    const zgltf = b.dependency("zgltf", .{});
    exe.root_module.addImport("zgltf", zgltf.module("zgltf"));

    // zobj
    const zobj = b.dependency("zobj", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zobj", zobj.module("obj"));

    // vulkan
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan = b.dependency("vulkan_zig", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    }).module("vulkan-zig");
    exe.root_module.addImport("vulkan", vulkan);

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
    if (!no_assets) {
        const assets_exe = b.addExecutable(.{
            .name = "saturn_assets",
            .root_source_file = b.path("src/asset_main.zig"),
            .target = target,
            .optimize = optimize,
        });

        assets_exe.root_module.addImport("zstbi", zstbi.module("root"));
        assets_exe.root_module.addImport("zobj", zobj.module("obj"));
        assets_exe.root_module.addImport("zgltf", zgltf.module("zgltf"));
        assets_exe.root_module.addImport("zmath", zmath.module("root"));

        const zdxc = b.dependency("zdxc", .{
            .target = target,
            .optimize = optimize,
        });
        assets_exe.root_module.addImport("dxc", zdxc.module("dxc"));

        b.installArtifact(assets_exe);
        const build_engine_assets = b.addRunArtifact(assets_exe);
        build_engine_assets.step.dependOn(b.getInstallStep());
        build_engine_assets.addArg("engine");
        build_engine_assets.addArg("assets/");
        build_engine_assets.addArg("zig-out/assets");

        //TODO: get this path from builder
        const run_engine_assets_step = b.step("engine_assets", "Process engine assets");
        run_engine_assets_step.dependOn(&build_engine_assets.step);

        const build_game_assets = b.addRunArtifact(assets_exe);
        build_game_assets.step.dependOn(b.getInstallStep());
        build_game_assets.addArg("game");
        build_game_assets.addArg("game-assets/");
        build_game_assets.addArg("zig-out/game-assets");

        //TODO: get this path from builder
        const run_game_assets_step = b.step("game_assets", "Process game assets");
        run_game_assets_step.dependOn(&build_game_assets.step);

        const run_assets_step = b.step("assets", "Process all assets");
        run_assets_step.dependOn(&build_engine_assets.step);
        run_assets_step.dependOn(&build_game_assets.step);
    }

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
