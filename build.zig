const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const build_sdl3 = b.option(bool, "build_sdl3", "Build and link sdl3 from source instead of using systemlib") orelse false;
    const no_assets = b.option(bool, "no_assets", "Don't compile asset pipeline") orelse false;
    const no_game = b.option(bool, "no_game", "Don't compile game project") orelse false;
    const no_render = b.option(bool, "no_render", "Don't compile render sandbox") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (!no_assets) {
        try buildAsset(b, target, optimize);
    }

    if (!no_game) {
        try buildGame(b, target, optimize, .{ .build_sdl3 = build_sdl3 });
    }

    if (!no_render) {
        try buildRender(b, target, optimize, .{ .build_sdl3 = build_sdl3 });
    }

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = unit_tests; // autofix
}

fn buildAsset(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    const exe = b.addExecutable(.{
        .name = "saturn_assets",
        .root_source_file = b.path("src/main_asset.zig"),
        .target = target,
        .optimize = optimize,
    });

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

    // zdxc
    const zdxc = b.dependency("zdxc", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("dxc", zdxc.module("dxc"));

    b.installArtifact(exe);
    const build_engine_assets = b.addRunArtifact(exe);
    build_engine_assets.step.dependOn(b.getInstallStep());
    build_engine_assets.addArg("engine");
    build_engine_assets.addArg("assets/");
    build_engine_assets.addArg("zig-out/assets");

    //TODO: get this path from builder
    const run_engine_assets_step = b.step("engine_assets", "Process engine assets");
    run_engine_assets_step.dependOn(&build_engine_assets.step);

    const build_game_assets = b.addRunArtifact(exe);
    build_game_assets.step.dependOn(b.getInstallStep());
    build_game_assets.addArg("game");
    build_game_assets.addArg("game-assets/");
    build_game_assets.addArg("zig-out/game-assets");

    //TODO: get this path from builder
    const run_game_assets_step = b.step("game-assets", "Process game assets");
    run_game_assets_step.dependOn(&build_game_assets.step);

    const run_assets_step = b.step("assets", "Process all assets");
    run_assets_step.dependOn(&build_engine_assets.step);
    run_assets_step.dependOn(&build_game_assets.step);
}

fn buildGame(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: struct {
        build_sdl3: bool = false,
    },
) !void {
    const exe = b.addExecutable(.{
        .name = "saturn",
        .root_source_file = b.path("src/main_game.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (options.build_sdl3) {
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

    // zlua
    const zlua = b.dependency("zlua", .{
        .target = target,
        .optimize = optimize,
        .lang = .lua54,
    });
    exe.root_module.addImport("zlua", zlua.module("zlua"));

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run-game", "Run the game");
    run_step.dependOn(&run_cmd.step);
}

fn buildRender(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: struct {
        build_sdl3: bool = false,
    },
) !void {
    const exe = b.addExecutable(.{
        .name = "saturn",
        .root_source_file = b.path("src/main_render.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (options.build_sdl3) {
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

    // zmath
    const zmath = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath.module("root"));

    // vulkan
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan = b.dependency("vulkan_zig", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    }).module("vulkan-zig");
    exe.root_module.addImport("vulkan", vulkan);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run-render", "Run the render sandbox");
    run_step.dependOn(&run_cmd.step);
}
