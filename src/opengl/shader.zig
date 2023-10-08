const std = @import("std");
const c = @import("../c.zig");

const Self = @This();

shader_program: c.GLuint,

pub fn init(vertex_shader: []const u8, fragment_shader: []const u8) Self {
    const stdout = std.io.getStdOut().writer();

    var program = c.glCreateProgram();

    var vertex_module = Self.init_shader_module(vertex_shader, c.GL_VERTEX_SHADER);
    c.glAttachShader(program, vertex_module);

    var fragment_module = Self.init_shader_module(fragment_shader, c.GL_FRAGMENT_SHADER);
    c.glAttachShader(program, fragment_module);

    c.glLinkProgram(program);

    var program_info_size: c.GLint = undefined;
    c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &program_info_size);
    if (program_info_size > 0) {
        var program_info_string = [_]u8{0} ** 512;
        c.glGetProgramInfoLog(program, @as(c.GLsizei, @intCast(program_info_string.len)), null, &program_info_string);
        stdout.print("Shader Error: {s}!\n", .{program_info_string}) catch {};
    }

    c.glDeleteShader(vertex_module);
    c.glDeleteShader(fragment_module);

    return Self{
        .shader_program = program,
    };
}

pub fn deinit(self: *Self) void {
    c.glDeleteProgram(self.shader_program);
}

fn init_shader_module(shader_code: []const u8, stage: c.GLuint) c.GLuint {
    var shader = c.glCreateShader(stage);
    c.glShaderSource(shader, 1, &shader_code.ptr, &@as(c.GLint, @intCast(shader_code.len)));
    c.glCompileShader(shader);
    return shader;
}
