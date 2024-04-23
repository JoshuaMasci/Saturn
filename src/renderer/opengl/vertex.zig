const gl = @import("zopengl").bindings;

pub const ColoredVertex = struct {
    const Self = @This();

    position: [3]f32,
    color: [3]f32,

    pub fn new(position: [3]f32, color: [3]f32) Self {
        return Self{
            .position = position,
            .color = color,
        };
    }

    pub fn genVao() void {
        gl.enableVertexAttribArray(0);
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Self), null); // Position is at zero
        gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(Self), @ptrFromInt(@offsetOf(Self, "color")));
    }
};

pub const TexturedVertex = struct {
    const Self = @This();

    position: [3]f32,
    uv: [3]f32,

    pub fn new(position: [3]f32, uv: [3]f32) Self {
        return Self{
            .position = position,
            .uv = uv,
        };
    }

    pub fn genVao() void {
        gl.enableVertexAttribArray(0);
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Self), null); // Position is at zero
        gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, @sizeOf(Self), @ptrFromInt(@offsetOf(Self, "uv")));
    }
};
