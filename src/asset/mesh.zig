const std = @import("std");
const serde = @import("../serde.zig");

pub const VertexPositions = [3]f32;
pub const VertexData = struct {
    normals: [3]f32,
    tangents: [4]f32,
    uv0: [2]f32,
};

pub const Primitive = struct {
    index_offset: u32,
    index_count: u32,
};

const Self = @This();

name: []u8,
primitives: []Primitive,
positions: []VertexPositions,
data: []VertexData,
indices: []u32,

pub fn serialize(self: Self, writer: anytype) !void {
    try serde.serialzieSlice(u8, writer, self.name);
    try serde.serialzieSlice(Primitive, writer, self.primitives);
    try serde.serialzieSlice(VertexPositions, writer, self.positions);
    try serde.serialzieSlice(VertexData, writer, self.data);
    try serde.serialzieSlice(u32, writer, self.indices);
}

pub fn deserialzie(reader: anytype, allocator: std.mem.Allocator) !Self {
    return .{
        .name = serde.deserialzieSlice(u8, reader, allocator),
        .primitives = serde.deserialzieSlice(Primitive, reader, allocator),
        .positions = serde.deserialzieSlice(VertexPositions, reader, allocator),
        .data = serde.deserialzieSlice(VertexData, reader, allocator),
        .indices = serde.deserialzieSlice(u32, reader, allocator),
    };
}
