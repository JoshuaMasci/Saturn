const std = @import("std");
const c = @import("../c.zig");

const panic = std.debug.panic;

const Self = @This();

vao: c.GLuint,
vertex_buffer: c.GLuint,
index_buffer: c.GLuint,
index_count: c.GLint,
index_type: c.GLenum,

fn isVertexTypeValid(comptime VertexType: type) void {
    if (!comptime std.meta.hasFn(VertexType, "genVao")) {
        @compileError("VertexType doesn't have genVao Function");
    }
}

fn getIndexType(comptime IndexType: type) c.GLenum {
    if (comptime IndexType == u8) {
        return c.GL_UNSIGNED_BYTE;
    } else if (comptime IndexType == u16) {
        return c.GL_UNSIGNED_SHORT;
    } else if (comptime IndexType == u32) {
        return c.GL_UNSIGNED_INT;
    } else {
        @compileError("IndexType must be u8, u16, or u32");
    }
}

pub fn init(comptime VertexType: type, comptime IndexType: type, vertices: []const VertexType, indices: []const IndexType) Self {
    //Validate Types
    comptime isVertexTypeValid(VertexType);
    const index_type: c.GLenum = comptime getIndexType(IndexType);

    var vao: c.GLuint = undefined;
    c.glGenVertexArrays(1, &vao);
    c.glBindVertexArray(vao);

    var buffers: [2]c.GLuint = undefined;
    c.glGenBuffers(buffers.len, &buffers);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, buffers[0]);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(@sizeOf(VertexType) * vertices.len), vertices.ptr, c.GL_STATIC_DRAW);
    VertexType.genVao();

    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, buffers[1]);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(IndexType) * indices.len), indices.ptr, c.GL_STATIC_DRAW);

    c.glBindVertexArray(0);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);

    return Self{
        .vao = vao,
        .vertex_buffer = buffers[0],
        .index_buffer = buffers[1],
        .index_count = @as(c.GLint, @intCast(indices.len)),
        .index_type = index_type,
    };
}

pub fn deinit(self: *const Self) void {
    c.glDeleteVertexArrays(1, &self.vao);
    c.glDeleteBuffers(1, &self.vertex_buffer);
    c.glDeleteBuffers(1, &self.index_buffer);
}

pub fn draw(self: *const Self) void {
    //Setup
    c.glBindVertexArray(self.vao);
    defer c.glBindVertexArray(0);
    defer c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.index_buffer);
    defer c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);

    //Draw
    c.glDrawElements(c.GL_TRIANGLES, self.index_count, self.index_type, null);
}
