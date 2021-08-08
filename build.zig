//Paths needed to be updated per system
const glfw_include_path = "C:/glfw-3.3.4/include";
const glfw_lib_path = "C:/glfw-3.3.4/lib-vc2019/";
const vk_xml_path = "C:/VulkanSDK/1.2.162.1/share/vulkan/registry/vk.xml";
const vk_glslc_path = "C:/VulkanSDK/1.2.162.1/Bin/glslc.exe";

//Hardcoded paths
const vkgen = @import("submodules/vulkan-zig/generator/index.zig");

const builtin = @import("builtin");
const std = @import("std");
const Step = std.build.Step;
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

    //Compile Builtin Shaders
    const res = ResourceGenStep.init(b, "resources.zig");
    res.addShader("tri_vert", "assets/tri.vert");
    res.addShader("tri_frag", "assets/tri.frag");
    exe.step.dependOn(&res.step);
    exe.addPackage(res.package);

    //Run program
    const play = b.step("run", "Run the engine");
    const run = exe.run();
    run.step.dependOn(b.getInstallStep());
    play.dependOn(&run.step);
}

pub const ResourceGenStep = struct {
    step: Step,
    shader_step: *vkgen.ShaderCompileStep,
    builder: *Builder,
    package: std.build.Pkg,
    resources: std.ArrayList(u8),

    pub fn init(builder: *Builder, out: []const u8) *ResourceGenStep {
        const self = builder.allocator.create(ResourceGenStep) catch unreachable;
        const full_out_path = std.fs.path.join(builder.allocator, &[_][]const u8{
            builder.build_root,
            builder.cache_root,
            out,
        }) catch unreachable;

        self.* = .{
            .step = Step.init(.Custom, "resources", builder.allocator, make),
            .shader_step = vkgen.ShaderCompileStep.init(builder, &[_][]const u8{ "glslc", "--target-env=vulkan1.2" }),
            .builder = builder,
            .package = .{
                .name = "resources",
                .path = full_out_path,
                .dependencies = null,
            },
            .resources = std.ArrayList(u8).init(builder.allocator),
        };

        self.step.dependOn(&self.shader_step.step);
        return self;
    }

    fn renderPath(path: []const u8, writer: anytype) void {
        const separators = &[_]u8{ std.fs.path.sep_windows, std.fs.path.sep_posix };
        var i: usize = 0;
        while (std.mem.indexOfAnyPos(u8, path, i, separators)) |j| {
            writer.writeAll(path[i..j]) catch unreachable;
            switch (std.fs.path.sep) {
                std.fs.path.sep_windows => writer.writeAll("\\\\") catch unreachable,
                std.fs.path.sep_posix => writer.writeByte(std.fs.path.sep_posix) catch unreachable,
                else => unreachable,
            }

            i = j + 1;
        }
        writer.writeAll(path[i..]) catch unreachable;
    }

    pub fn addShader(self: *ResourceGenStep, name: []const u8, source: []const u8) void {
        const shader_out_path = self.shader_step.add(source);
        var writer = self.resources.writer();

        writer.print("pub const {s} = @embedFile(\"", .{name}) catch unreachable;
        renderPath(shader_out_path, writer);
        writer.writeAll("\");\n") catch unreachable;
    }

    fn make(step: *Step) !void {
        const self = @fieldParentPtr(ResourceGenStep, "step", step);
        const cwd = std.fs.cwd();

        const dir = std.fs.path.dirname(self.package.path).?;
        try cwd.makePath(dir);
        try cwd.writeFile(self.package.path, self.resources.items);
    }
};
