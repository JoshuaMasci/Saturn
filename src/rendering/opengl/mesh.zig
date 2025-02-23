const std = @import("std");
const gl = @import("zopengl").bindings;

const MeshAsset = @import("../../asset/mesh.zig");

const Self = @This();

vao: gl.Uint,
vertex_buffer: gl.Uint,
index_buffer: gl.Uint,
vertex_count: gl.Int,
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

pub fn init(mesh: *const MeshAsset) Self {
    const index_type: gl.Enum = gl.UNSIGNED_INT;

    var vao: gl.Uint = undefined;
    gl.genVertexArrays(1, &vao);
    gl.bindVertexArray(vao);

    var buffers: [2]gl.Uint = undefined;
    gl.genBuffers(buffers.len, &buffers);

    gl.bindBuffer(gl.ARRAY_BUFFER, buffers[0]);

    const vertex_count = mesh.positions.len;
    std.debug.assert(mesh.positions.len == mesh.attributes.len);

    const position_size = @sizeOf(MeshAsset.VertexPositions);
    const attributes_size = @sizeOf(MeshAsset.VertexAttributes);

    const position_byte_len = position_size * vertex_count;
    const attributes_byte_len = attributes_size * vertex_count;
    gl.bufferData(gl.ARRAY_BUFFER, @intCast(position_byte_len + attributes_byte_len), null, gl.STATIC_DRAW);
    gl.bufferSubData(gl.ARRAY_BUFFER, 0, @intCast(position_byte_len), mesh.positions.ptr);
    gl.bufferSubData(gl.ARRAY_BUFFER, @intCast(position_byte_len), @intCast(attributes_byte_len), mesh.attributes.ptr);

    {
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, position_size, null);

        gl.enableVertexAttribArray(1);
        gl.enableVertexAttribArray(2);
        gl.enableVertexAttribArray(3);
        gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, attributes_size, @ptrFromInt(position_byte_len + @offsetOf(MeshAsset.VertexAttributes, "normal")));
        gl.vertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, attributes_size, @ptrFromInt(position_byte_len + @offsetOf(MeshAsset.VertexAttributes, "tangent")));
        gl.vertexAttribPointer(3, 2, gl.FLOAT, gl.FALSE, attributes_size, @ptrFromInt(position_byte_len + @offsetOf(MeshAsset.VertexAttributes, "uv0")));
    }

    const index_count = mesh.indices.len;

    if (index_count != 0) {
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffers[1]);
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(u32) * index_count), mesh.indices.ptr, gl.STATIC_DRAW);
    }

    gl.bindVertexArray(0);
    gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

    return Self{
        .vao = vao,
        .vertex_buffer = buffers[0],
        .index_buffer = buffers[1],
        .vertex_count = @intCast(vertex_count),
        .index_count = @intCast(index_count),
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

    if (self.index_count != 0) {
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.index_buffer);
        defer gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

        //Draw
        gl.drawElements(gl.TRIANGLES, self.index_count, self.index_type, null);
    } else {
        gl.drawArrays(gl.TRIANGLES, 0, self.vertex_count);
    }
}
