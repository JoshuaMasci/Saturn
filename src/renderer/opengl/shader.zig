const std = @import("std");
const gl = @import("zopengl").bindings;
const zm = @import("zmath");

const Self = @This();

shader_program: gl.Uint,

pub fn init(vertex_shader: []const u8, fragment_shader: []const u8) Self {
    const stdout = std.io.getStdOut().writer();

    const program = gl.createProgram();

    const vertex_module = Self.init_shader_module(vertex_shader, gl.VERTEX_SHADER);
    gl.attachShader(program, vertex_module);

    const fragment_module = Self.init_shader_module(fragment_shader, gl.FRAGMENT_SHADER);
    gl.attachShader(program, fragment_module);

    gl.linkProgram(program);

    var program_info_size: gl.Int = undefined;
    gl.getProgramiv(program, gl.INFO_LOG_LENGTH, &program_info_size);
    if (program_info_size > 0) {
        var program_info_string = [_]u8{0} ** 512;
        gl.getProgramInfoLog(program, @as(gl.Sizei, @intCast(program_info_string.len)), null, &program_info_string);
        stdout.print("Shader Error: {s}!\n", .{program_info_string}) catch {};
    }

    gl.deleteShader(vertex_module);
    gl.deleteShader(fragment_module);

    return Self{
        .shader_program = program,
    };
}

pub fn deinit(self: *Self) void {
    gl.deleteProgram(self.shader_program);
}

fn init_shader_module(shader_code: []const u8, stage: gl.Uint) gl.Uint {
    const shader = gl.createShader(stage);
    gl.shaderSource(shader, 1, &shader_code.ptr, &@intCast(shader_code.len));
    gl.compileShader(shader);
    return shader;
}

pub fn bind(self: Self) void {
    gl.useProgram(self.shader_program);
}

pub fn set_uniform_mat4(self: Self, name: []const u8, mat: *const zm.Mat) void {
    const uniform_index = gl.getUniformLocation(self.shader_program, name.ptr);
    std.debug.assert(uniform_index != gl.INVALID_VALUE);
    gl.uniformMatrix4fv(uniform_index, 1, gl.FALSE, &zm.matToArr(mat.*));
}
