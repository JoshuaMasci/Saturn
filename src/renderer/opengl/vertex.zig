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
    normal: [3]f32,
    tangent: [4]f32,
    uv0: [3]f32,

    pub fn new(position: [3]f32, normal: [3]f32, tangent: [4]f32, uv0: [3]f32) Self {
        return Self{
            .position = position,
            .normal = normal,
            .tangent = tangent,
            .uv0 = uv0,
        };
    }

    pub fn genVao() void {
        gl.enableVertexAttribArray(0);
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf(Self), @ptrFromInt(@offsetOf(Self, "position")));
        gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, @sizeOf(Self), @ptrFromInt(@offsetOf(Self, "normal")));
        gl.vertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, @sizeOf(Self), @ptrFromInt(@offsetOf(Self, "tanget")));
        gl.vertexAttribPointer(3, 2, gl.FLOAT, gl.FALSE, @sizeOf(Self), @ptrFromInt(@offsetOf(Self, "uv0")));
    }
};
