const std = @import("std");
const gl = @import("zopengl").bindings;

const Self = @This();

vao: gl.Uint,
vertex_buffer: gl.Uint,
index_buffer: gl.Uint,
index_count: gl.Int,
index_type: gl.Enum,

fn isVertexTypeValid(comptime VertexType: type) void {
    if (!comptime std.meta.hasFn(VertexType, "genVao")) {
        @compileError("VertexType doesn't have genVao Function");
    }
}

fn getIndexType(comptime IndexType: type) gl.Enum {
    if (comptime IndexType == u8) {
        return gl.UNSIGNED_BYTE;
    } else if (comptime IndexType == u16) {
        return gl.UNSIGNED_SHORT;
    } else if (comptime IndexType == u32) {
        return gl.UNSIGNED_INT;
    } else {
        @compileError("IndexType must be u8, u16, or u32");
    }
}

pub fn init(comptime VertexType: type, comptime IndexType: type, vertices: []const VertexType, indices: []const IndexType) Self {
    //Validate Types
    comptime isVertexTypeValid(VertexType);
    const index_type: gl.Enum = comptime getIndexType(IndexType);

    var vao: gl.Uint = undefined;
    gl.genVertexArrays(1, &vao);
    gl.bindVertexArray(vao);

    var buffers: [2]gl.Uint = undefined;
    gl.genBuffers(buffers.len, &buffers);

    gl.bindBuffer(gl.ARRAY_BUFFER, buffers[0]);
    gl.bufferData(gl.ARRAY_BUFFER, @intCast(@sizeOf(VertexType) * vertices.len), vertices.ptr, gl.STATIC_DRAW);
    VertexType.genVao();

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffers[1]);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(IndexType) * indices.len), indices.ptr, gl.STATIC_DRAW);

    gl.bindVertexArray(0);
    gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

    return Self{
        .vao = vao,
        .vertex_buffer = buffers[0],
        .index_buffer = buffers[1],
        .index_count = @intCast(indices.len),
        .index_type = index_type,
    };
}

pub fn deinit(self: *const Self) void {
    gl.deleteVertexArrays(1, &self.vao);
    gl.deleteBuffers(1, &self.vertex_buffer);
    gl.deleteBuffers(1, &self.index_buffer);
}

pub fn draw(self: *const Self) void {
    //Setup
    gl.bindVertexArray(self.vao);
    defer gl.bindVertexArray(0);

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.index_buffer);
    defer gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

    //Draw
    gl.drawElements(gl.TRIANGLES, self.index_count, self.index_type, null);
}
