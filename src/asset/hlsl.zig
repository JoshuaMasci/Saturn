const std = @import("std");
const Shader = @import("shader.zig");

const c = @cImport({
    @cInclude("SDL3_shadercross/SDL_shadercross.h");
});

pub fn init() bool {
    return !c.SDL_ShaderCross_Init();
}

pub fn deinit() void {
    c.SDL_ShaderCross_Quit();
}

pub fn compileShader(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !Shader {
    const file_buffer = try dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, 0);
    defer allocator.free(file_buffer);

    const shader_name: []const u8 = try copyBytes(allocator, removeExt(file_path), null);
    errdefer allocator.free(shader_name);

    const shader_ext = std.fs.path.extension(shader_name);

    var shader_stage: Shader.Stage = undefined;
    if (std.mem.eql(u8, shader_ext, ".vert")) {
        shader_stage = .vertex;
    } else if (std.mem.eql(u8, shader_ext, ".frag")) {
        shader_stage = .fragment;
    } else if (std.mem.eql(u8, shader_ext, ".comp")) {
        shader_stage = .compute;
    } else {
        return error.unknownShaderType;
    }

    var hlsl_info = c.SDL_ShaderCross_HLSL_Info{
        .source = @ptrCast(file_buffer),
        .entrypoint = "main",
        .include_dir = null, //TODO: support an include dir
        .defines = null, //TODO: support defines
        .shader_stage = switch (shader_stage) {
            .vertex => c.SDL_SHADERCROSS_SHADERSTAGE_VERTEX,
            .fragment => c.SDL_SHADERCROSS_SHADERSTAGE_FRAGMENT,
            .compute => c.SDL_SHADERCROSS_SHADERSTAGE_COMPUTE,
        },
        .enable_debug = false, //TODO: make this a setting
        .name = @ptrCast(shader_name),
    };

    // SPIRV
    var spirv_size: usize = 0;
    const spirv_code_ptr: [*]u8 = @ptrCast(c.SDL_ShaderCross_CompileSPIRVFromHLSL(&hlsl_info, &spirv_size) orelse return error.failedToCompileSPIRV);
    defer c.SDL_free(spirv_code_ptr);

    var meta_data: c.SDL_ShaderCross_GraphicsShaderMetadata = undefined;
    if (!c.SDL_ShaderCross_ReflectGraphicsSPIRV(spirv_code_ptr, spirv_size, @ptrCast(&meta_data))) {
        return error.failedtoReflectSPIRV;
    }

    const spirv_code: []u8 = try copyBytes(allocator, spirv_code_ptr[0..spirv_size], null);
    errdefer allocator.free(spirv_code);

    const shader = Shader{
        .name = shader_name,
        .stage = shader_stage,
        .bindings = .{
            .samplers = meta_data.num_samplers,
            .storage_textures = meta_data.num_storage_textures,
            .uniform_buffers = meta_data.num_uniform_buffers,
            .storage_buffers = meta_data.num_storage_buffers,
        },
        .spirv_code = spirv_code,
    };

    return shader;
}

//TODO: need utils module
fn copyBytes(allocator: std.mem.Allocator, bytes: []const u8, sentinel: ?u8) ![]u8 {
    // Calculate the length of the new slice (bytes + sentinel if present)
    var new_len = bytes.len;
    if (sentinel) |_| {
        new_len += 1;
    }

    // Allocate the new buffer to hold the original bytes + sentinel (if present)
    var buffer = try allocator.alloc(u8, new_len);

    // Copy the original bytes into the buffer
    @memcpy(buffer[0..bytes.len], bytes);

    // If a sentinel is provided, append it
    if (sentinel) |s| {
        buffer[bytes.len] = s;
    }

    return buffer;
}

fn removeExt(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    return path[0..(path.len - ext.len)];
}
