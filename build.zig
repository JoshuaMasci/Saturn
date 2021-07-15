const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    var exe = b.addExecutable("ZigCraft", "src/main.zig");

    exe.setBuildMode(mode);
    exe.install();

    exe.addIncludeDir("src");

    //glfw
    exe.addIncludeDir("C:/zig_glfw/include");
    exe.addLibPath("C:/zig_glfw/build/src/Release");
    exe.linkSystemLibrary("glfw3");

    //vulkan
    exe.addIncludeDir("C:/VulkanSDK/1.2.162.1/Include");
    exe.addLibPath("C:/VulkanSDK/1.2.162.1/Lib/");
    exe.linkSystemLibrary("vulkan-1");

    exe.linkLibC();

    //OS specific libraries
    switch (builtin.os.tag) {
        .windows => {
            exe.linkSystemLibrary("kernel32");
            exe.linkSystemLibrary("user32");
            exe.linkSystemLibrary("shell32");
            exe.linkSystemLibrary("gdi32");
            exe.linkSystemLibrary("uuid");
        },
        .linux => {
            //Add linux libraries if needed
        },
        else => {
            @compileError("Platform not supported, unsure of build requirements");
        },
    }

    const play = b.step("run", "Run the engine");
    const run = exe.run();
    run.step.dependOn(b.getInstallStep());
    play.dependOn(&run.step);
}