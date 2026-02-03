const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const build_sdl3 = b.option(bool, "build-sdl3", "Build and link sdl3 from source instead of using systemlib") orelse false;
    const no_assets = b.option(bool, "no-assets", "Don't compile asset pipeline") orelse false;
    const no_main = b.option(bool, "no-render", "Don't compile main sandbox") orelse false;
    const use_llvm = b.option(bool, "use-llvm", "Compile using llvm") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (!no_assets) {
        try buildAsset(
            b,
            target,
            optimize,
            .{
                .use_llvm = use_llvm,
            },
        );
    }

    if (!no_main) {
        try buildMain(
            b,
            target,
            optimize,
            .{
                .build_sdl3 = build_sdl3,
                .use_llvm = use_llvm,
            },
        );
    }
}

fn buildAsset(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: struct {
        use_llvm: bool,
    },
) !void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main_asset.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    // zmath
    const zmath = b.dependency("zmath", .{});
    exe_mod.addImport("zmath", zmath.module("root"));

    // zstbi
    const zstbi = b.dependency("zstbi", .{});
    exe_mod.addImport("zstbi", zstbi.module("root"));

    // zgltf
    const zgltf = b.dependency("zgltf", .{});
    exe_mod.addImport("zgltf", zgltf.module("zgltf"));

    // zobj
    const zobj = b.dependency("obj", .{ .target = target, .optimize = optimize });
    exe_mod.addImport("zobj", zobj.module("obj"));

    // Glsl compiler
    exe_mod.linkSystemLibrary("glslang", .{});
    exe_mod.linkSystemLibrary("glslang-default-resource-limits", .{});

    // meshoptimizer
    // TODO: build from source
    exe_mod.linkSystemLibrary("meshoptimizer", .{});

    const exe = b.addExecutable(.{
        .name = "saturn_asset",
        .root_module = exe_mod,
        .use_llvm = options.use_llvm,
    });

    b.installArtifact(exe);

    const ASSET_REGISTRIES = [_][]const u8{ "engine", "game" };

    const run_assets_step = b.step("assets", "Process all assets");

    inline for (ASSET_REGISTRIES) |registry_name| {
        run_assets_step.dependOn(buildAssetRegistry(b, exe, registry_name));
    }

    // const build_engine_assets = b.addRunArtifact(exe);
    // build_engine_assets.step.dependOn(b.getInstallStep());
    // build_engine_assets.addArg("engine");
    // build_engine_assets.addArg("assets/");
    // build_engine_assets.addArg("zig-out/assets");

    // //TODO: get this path from builder
    // const run_engine_assets_step = b.step("engine-assets", "Process engine assets");
    // run_engine_assets_step.dependOn(&build_engine_assets.step);

    // const build_game_assets = b.addRunArtifact(exe);
    // build_game_assets.step.dependOn(b.getInstallStep());
    // build_game_assets.addArg("game");
    // build_game_assets.addArg("game-assets/");
    // build_game_assets.addArg("zig-out/game-assets");

    // //TODO: get this path from builder
    // const run_game_assets_step = b.step("game-assets", "Process game assets");
    // run_game_assets_step.dependOn(&build_game_assets.step);

    // const run_assets_step = b.step("assets", "Process all assets");
    // run_assets_step.dependOn(&build_engine_assets.step);
    // run_assets_step.dependOn(&build_game_assets.step);
}

fn buildAssetRegistry(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    comptime registry_name: []const u8,
) *std.Build.Step {
    const run_artifact = b.addRunArtifact(exe);
    run_artifact.step.dependOn(b.getInstallStep());
    run_artifact.addArg(registry_name);
    run_artifact.addArg("assets/" ++ registry_name ++ "/");
    run_artifact.addArg("zig-out/assets/" ++ registry_name ++ "/");

    const run_assets_step = b.step(registry_name ++ "-assets", "Process " ++ registry_name ++ " assets");
    run_assets_step.dependOn(&run_artifact.step);

    return &run_artifact.step;
}

fn buildMain(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: struct {
        build_sdl3: bool,
        use_llvm: bool,
    },
) !void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (options.build_sdl3) {
        const sdl3 = b.lazyDependency("sdl", .{
            .target = target,
            .optimize = optimize,
            .preferred_linkage = .dynamic,
        }).?;
        exe_mod.linkLibrary(sdl3.artifact("SDL3"));
    } else {
        exe_mod.linkSystemLibrary("SDL3", .{ .preferred_link_mode = .dynamic });
    }

    // vulkan
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan = b.dependency("vulkan", .{
        .registry = vulkan_headers.path("registry/vk.xml"),
    }).module("vulkan-zig");
    exe_mod.addImport("vulkan", vulkan);

    const cimgui = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platform = .SDL3,
        .renderer = .Vulkan,
    });
    exe_mod.linkLibrary(cimgui.artifact("cimgui"));

    // zmath
    const zmath = b.dependency("zmath", .{});
    exe_mod.addImport("zmath", zmath.module("root"));

    const exe = b.addExecutable(.{
        .name = "saturn",
        .root_module = exe_mod,
        .use_llvm = options.use_llvm,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the render sandbox");
    run_step.dependOn(&run_cmd.step);
}
