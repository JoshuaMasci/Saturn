const std = @import("std");
const serde = @import("../serde.zig");

pub const Registry = @import("system.zig").AssetSystem(Self, &[_][]const u8{".mesh"});

const MAGIC: [8]u8 = .{ 'S', 'A', 'T', '-', 'M', 'E', 'S', 'H' };
const VERSION: usize = 1;

//TODO: can compress this down by storing types in ints
pub const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    tangent: [4]f32,
    uv0: [2]f32,
    uv1: [2]f32,
};

pub const Primitive = struct {
    sphere_pos_radius: [4]f32,
    vertices: []Vertex,
    indices: []u32,
};

const Self = @This();

name: []const u8,
primitives: []Primitive,

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    for (self.primitives) |primitive| {
        allocator.free(primitive.vertices);
        allocator.free(primitive.indices);
    }
    allocator.free(self.primitives);
}

pub fn serialize(self: Self, writer: std.fs.File.Writer) !void {
    try writer.writeAll(&MAGIC);
    try writer.writeInt(usize, VERSION, .little);
    try serde.serialzieSlice(u8, writer, self.name);

    try writer.writeInt(usize, self.primitives.len, .little);
    for (self.primitives) |primitive| {

        //TODO: find better serialization for float array
        try serde.serialzieSlice(f32, writer, &primitive.sphere_pos_radius);

        try serde.serialzieSlice(Vertex, writer, primitive.vertices);
        try serde.serialzieSlice(u32, writer, primitive.indices);
    }
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: std.fs.File.Reader) !Self {
    var magic: [8]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &MAGIC, &magic)) {
        return error.InvalidMagic;
    }
    const version = try reader.readInt(usize, .little);
    if (version != VERSION) {
        return error.InvalidVersion;
    }

    const name = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(name);

    const primitives_count = try reader.readInt(usize, .little);
    var primitives = try allocator.alloc(Primitive, primitives_count);
    for (0..primitives_count) |i| {
        const float_slice: []f32 = try serde.deserialzieSlice(allocator, f32, reader);
        defer allocator.free(float_slice);
        @memcpy(&primitives[i].sphere_pos_radius, float_slice[0..4]);

        primitives[i].vertices = try serde.deserialzieSlice(allocator, Vertex, reader);
        primitives[i].indices = try serde.deserialzieSlice(allocator, u32, reader);
    }

    return .{
        .name = name,
        .primitives = primitives,
    };
}
