const c = @import("../c.zig");

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
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Self), null); // Position is at zero
        c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Self), @ptrFromInt(@offsetOf(Self, "color")));
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
        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Self), null); // Position is at zero
        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Self), @ptrFromInt(@offsetOf(Self, "uv")));
    }
};
