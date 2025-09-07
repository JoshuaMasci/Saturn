const std = @import("std");

const dxc = @import("dxc");

const Shader = @import("shader.zig");

pub const DirectoryMeta = Shader.DirectoryMeta;

pub fn dupeBytesToU32(allocator: std.mem.Allocator, input: []const u8) ![]u32 {
    if (input.len % 4 != 0)
        return error.InputLengthNotMultipleOf4;

    const output = try allocator.alloc(u32, input.len / 4);

    for (output, 0..) |*out_val, i| {
        const bytes = input[i * 4 ..][0..4];
        out_val.* = std.mem.readInt(u32, bytes, .little);
    }

    return output;
}

pub fn getShaderStage(ext: []const u8) ?Shader.Stage {
    if (std.mem.eql(u8, ext, ".vert")) {
        return .vertex;
    } else if (std.mem.eql(u8, ext, ".frag")) {
        return .fragment;
    } else if (std.mem.eql(u8, ext, ".comp")) {
        return .compute;
    } else {
        return null;
    }
}

pub const Compiler = struct {
    const Self = @This();

    compiler: dxc.Compiler,
    settings: DirectoryMeta,

    pub fn init(
        allocator: std.mem.Allocator,
        dir: std.fs.Dir,
        settings: DirectoryMeta,
    ) !Self {
        var compiler: dxc.Compiler = try .init();
        errdefer compiler.deinit();

        for (settings.include_directories) |include_dir| {
            try compiler.addIncludeDirectory(allocator, dir, include_dir);
        }

        return .{
            .compiler = compiler,
            .settings = settings,
        };
    }

    pub fn deinit(self: Self) void {
        self.compiler.deinit();
    }

    pub fn compile(self: Self, allocator: std.mem.Allocator, shader_name: []const u8, shader_code: []const u8, shader_stage: Shader.Stage) !Shader {
        const profile = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ shader_stage.getProfileString(), self.settings.target_profile });
        defer allocator.free(profile);

        const compile_result = try self.compiler.compileHlslToSpirv(allocator, shader_name, shader_code, "main", profile);
        defer compile_result.deinit();

        const spirv_code: []u32 = try dupeBytesToU32(allocator, compile_result.spirv_data);
        errdefer allocator.free(spirv_code);

        return .{
            .name = try allocator.dupe(u8, shader_name),
            .target = .vulkan,
            .stage = shader_stage,
            .bindings = .{},
            .spirv_code = spirv_code,
        };
    }
};
