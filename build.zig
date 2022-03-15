//Paths needed to be updated per system
//TODO: create config file for it
const vk_xml_path = "C:/VulkanSDK/1.3.204.0/share/vulkan/registry/vk.xml";

//Submodules paths
const vkgen = @import("submodules/vulkan-zig/generator/index.zig");
const glfw = @import("submodules/mach-glfw/build.zig");

const builtin = @import("builtin");
const std = @import("std");
const Step = std.build.Step;
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub fn build(b: *Builder) void {
    var exe = b.addExecutable("Saturn", "src/main.zig");
    exe.install();

    const target = b.standardTargetOptions(.{});
    exe.setTarget(target);
    const mode = b.standardReleaseOptions();
    exe.setBuildMode(mode);

    exe.linkLibC();

    //mach-glfw
    exe.addPackagePath("glfw", "submodules/mach-glfw/src/main.zig");
    glfw.link(b, exe, .{});

    //cimgui
    exe.addIncludeDir("submodules/cimgui/"); //TODO: zig-ify the headers
    exe.linkLibrary(imguiLibrary(b, exe));

    //Vulkan Bindings
    const vk_gen = vkgen.VkGenerateStep.init(b, vk_xml_path, "vk.zig");
    exe.step.dependOn(&vk_gen.step);
    exe.addPackage(vk_gen.package);

    //Compile Builtin Shaders
    const res = ResourceGenStep.init(b, "resources.zig");
    res.addShader("tri_vert", "assets/tri.vert");
    res.addShader("tri_frag", "assets/tri.frag");

    res.addShader("imgui_vert", "assets/imgui.vert");
    res.addShader("imgui_frag", "assets/imgui.frag");

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
    output_file: std.build.GeneratedFile,
    resources: std.ArrayList(u8),

    pub fn init(builder: *Builder, out: []const u8) *ResourceGenStep {
        const self = builder.allocator.create(ResourceGenStep) catch unreachable;
        const full_out_path = std.fs.path.join(builder.allocator, &[_][]const u8{
            builder.build_root,
            builder.cache_root,
            out,
        }) catch unreachable;

        self.* = .{
            .step = Step.init(.custom, "resources", builder.allocator, make),
            .shader_step = vkgen.ShaderCompileStep.init(builder, &[_][]const u8{ "glslc", "--target-env=vulkan1.2" }, "shaders"),
            .builder = builder,
            .package = .{
                .name = "resources",
                .path = .{ .generated = &self.output_file },
                .dependencies = null,
            },
            .output_file = .{
                .step = &self.step,
                .path = full_out_path,
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

        const dir = std.fs.path.dirname(self.output_file.path.?).?;
        try cwd.makePath(dir);
        try cwd.writeFile(self.output_file.path.?, self.resources.items);
    }
};

//TODO: move to seprate package???
pub fn imguiLibrary(b: *Builder, step: *std.build.LibExeObjStep) *std.build.LibExeObjStep {
    var lib = b.addStaticLibrary("imgui", null);
    lib.setBuildMode(step.build_mode);
    lib.setTarget(step.target);

    lib.linkLibC();
    lib.linkSystemLibrary("c++");

    lib.addIncludeDir("submodules/cimgui/");
    lib.addIncludeDir("submodules/cimgui/imgui");

    const cpp_args = [_][]const u8{"-Wno-return-type-c-linkage"};
    lib.addCSourceFile("submodules/cimgui/imgui/imgui.cpp", &cpp_args);
    lib.addCSourceFile("submodules/cimgui/imgui/imgui_demo.cpp", &cpp_args);
    lib.addCSourceFile("submodules/cimgui/imgui/imgui_draw.cpp", &cpp_args);
    lib.addCSourceFile("submodules/cimgui/imgui/imgui_widgets.cpp", &cpp_args);
    lib.addCSourceFile("submodules/cimgui/imgui/imgui_tables.cpp", &cpp_args);
    lib.addCSourceFile("submodules/cimgui/cimgui.cpp", &cpp_args);

    return lib;
}
