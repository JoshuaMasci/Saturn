const std = @import("std");
const Shader = @import("shader.zig");

const c = @cImport({
    @cInclude("SDL3_shadercross/SDL_shadercross.h");
});

pub fn compileShader(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !Shader {
    _ = allocator; // autofix
    _ = dir; // autofix
    _ = file_path; // autofix

    if (!c.SDL_ShaderCross_Init())
        return error.failedToInitShaderCross;
    defer c.SDL_ShaderCross_Quit();

    return error.idk;
}
