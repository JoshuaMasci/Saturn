const glfw_include_path = "C:/glfw-3.3.4/include";
const glfw_lib_path = "C:/glfw-3.3.4/lib-vc2019/";
const vk_xml_path = "C:/VulkanSDK/1.2.162.1/share/vulkan/registry/vk.xml";

const vkgen = @import("submodules/vulkan-zig/generator/index.zig");

const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    var exe = b.addExecutable("Saturn", "src/main.zig");

    exe.setBuildMode(mode);
    exe.install();

    exe.linkLibC();

    //OS specific libraries
    switch (builtin.os.tag) {
        .windows => {
            exe.linkSystemLibrary("kernel32");
            exe.linkSystemLibrary("user32");
            exe.linkSystemLibrary("shell32");
            exe.linkSystemLibrary("gdi32");

            exe.addIncludeDir(glfw_include_path);
            exe.addLibPath(glfw_lib_path);

            //Use dll since zig 0.8.0 doesn't like static win glfw
            exe.linkSystemLibrary("glfw3dll");
            b.installBinFile(glfw_lib_path ++ "glfw3.dll", "glfw3.dll");
        },
        .linux => {
            exe.linkSystemLibrary("glfw3");
        },
        else => {
            @compileError("Platform not supported, unsure of build requirements");
        },
    }

    //Vulkan Bindings
    const vk_gen = vkgen.VkGenerateStep.init(b, vk_xml_path, "vk.zig");
    exe.step.dependOn(&vk_gen.step);
    exe.addPackage(vk_gen.package);

    const play = b.step("run", "Run the engine");
    const run = exe.run();
    run.step.dependOn(b.getInstallStep());
    play.dependOn(&run.step);
}
