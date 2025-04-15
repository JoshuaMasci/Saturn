const std = @import("std");
const serde = @import("../serde.zig");

pub const Registry = @import("system.zig").AssetSystem(Self, &[_][]const u8{".mesh"});

const MAGIC: [8]u8 = .{ 'S', 'A', 'T', '-', 'M', 'E', 'S', 'H' };

pub const VertexPositions = [3]f32;
pub const VertexAttributes = struct {
    normal: [3]f32,
    tangent: [4]f32,
    uv0: [2]f32,
};

pub const Primitive = struct {
    index_offset: u32,
    index_count: u32,
};

const Self = @This();

name: []const u8,
primitives: []Primitive,
positions: []VertexPositions,
attributes: []VertexAttributes,
indices: []u32,

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    allocator.free(self.primitives);
    allocator.free(self.positions);
    allocator.free(self.attributes);
    allocator.free(self.indices);
}

pub fn serialize(self: Self, writer: anytype) !void {
    try writer.writeAll(&MAGIC);
    try serde.serialzieSlice(u8, writer, self.name);
    try serde.serialzieSlice(Primitive, writer, self.primitives);
    try serde.serialzieSlice(VertexPositions, writer, self.positions);
    try serde.serialzieSlice(VertexAttributes, writer, self.attributes);
    try serde.serialzieSlice(u32, writer, self.indices);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype) !Self {
    var magic: [8]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &MAGIC, &magic)) {
        return error.InvalidMagic;
    }

    const name = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(name);

    const primitives = try serde.deserialzieSlice(allocator, Primitive, reader);
    errdefer allocator.free(primitives);

    const positions = try serde.deserialzieSlice(allocator, VertexPositions, reader);
    errdefer allocator.free(positions);

    const attributes = try serde.deserialzieSlice(allocator, VertexAttributes, reader);
    errdefer allocator.free(attributes);

    const indices = try serde.deserialzieSlice(allocator, u32, reader);
    errdefer allocator.free(indices);

    return .{
        .name = name,
        .primitives = primitives,
        .positions = positions,
        .attributes = attributes,
        .indices = indices,
    };
}
