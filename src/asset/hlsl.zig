const std = @import("std");
const Shader = @import("shader.zig");

pub fn compileShader(allocator: std.mem.Allocator, dir: std.fs.Dir, meta_file_path: []const u8) !Shader {
    const meta_file_buffer = try dir.readFileAllocOptions(allocator, meta_file_path, std.math.maxInt(usize), null, 4, 0);
    defer allocator.free(meta_file_buffer);
    const meta_data: Shader.Meta = try std.zon.parse.fromSlice(Shader.Meta, allocator, meta_file_buffer, null, .{});

    const file_path = removeExt(meta_file_path);

    const shader_code = try dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, 0);
    defer allocator.free(shader_code);

    const shader_name: []const u8 = try allocator.dupe(u8, file_path);
    errdefer allocator.free(shader_name);

    var shader_stage: Shader.Stage = undefined;
    const shader_ext = std.fs.path.extension(shader_name);
    if (std.mem.eql(u8, shader_ext, ".vert")) {
        shader_stage = .vertex;
    } else if (std.mem.eql(u8, shader_ext, ".frag")) {
        shader_stage = .fragment;
    } else if (std.mem.eql(u8, shader_ext, ".comp")) {
        shader_stage = .compute;
    } else {
        return error.unknownShaderType;
    }

    return switch (meta_data.target) {
        .vulkan => try compileVulkanShader(allocator, shader_name, shader_code, shader_stage),
    };
}

fn compileVulkanShader(allocator: std.mem.Allocator, shader_name: []const u8, shader_code: []const u8, shader_stage: Shader.Stage) !Shader {
    const dxc = @import("dxc");

    const compile_result = switch (shader_stage) {
        .vertex => try dxc.compileVertexShader(allocator, shader_code, "main"),
        .fragment => try dxc.compilePixelShader(allocator, shader_code, "main"),
        .compute => try dxc.compileComputeShader(allocator, shader_code, "main"),
    };
    defer compile_result.deinit();

    const spirv_code: []u32 = try dupeBytesToU32(allocator, compile_result.spirv_data);
    errdefer allocator.free(spirv_code);

    return .{
        .name = shader_name,
        .target = .vulkan,
        .stage = shader_stage,
        .bindings = .{},
        .spirv_code = spirv_code,
    };
}

fn removeExt(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    return path[0..(path.len - ext.len)];
}

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
