const std = @import("std");

const zmath = @import("zmath");

const serde = @import("../serde.zig");

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
sphere_pos_radius: [4]f32,
primitives: []Primitive,

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    for (self.primitives) |primitive| {
        allocator.free(primitive.vertices);
        allocator.free(primitive.indices);
    }
    allocator.free(self.primitives);
}

pub fn serialize(self: Self, writer: *std.Io.Writer) !void {
    try serde.serialzieSlice(u8, writer, self.name);

    try writer.writeAll(&std.mem.toBytes(self.sphere_pos_radius));

    try writer.writeInt(usize, self.primitives.len, .little);
    for (self.primitives) |primitive| {
        try writer.writeAll(&std.mem.toBytes(primitive.sphere_pos_radius));

        try serde.serialzieSlice(Vertex, writer, primitive.vertices);
        try serde.serialzieSlice(u32, writer, primitive.indices);
    }
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype) !Self {
    const name = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(name);

    var sphere_pos_radius: [4]f32 = undefined;
    _ = try reader.readAll(std.mem.asBytes(&sphere_pos_radius));

    const primitives_count = try reader.readInt(usize, .little);
    var primitives = try allocator.alloc(Primitive, primitives_count);
    for (0..primitives_count) |i| {
        _ = try reader.readAll(std.mem.asBytes(&primitives[i].sphere_pos_radius));

        primitives[i].vertices = try serde.deserialzieSlice(allocator, Vertex, reader);
        primitives[i].indices = try serde.deserialzieSlice(allocator, u32, reader);
    }

    return .{
        .name = name,
        .sphere_pos_radius = sphere_pos_radius,
        .primitives = primitives,
    };
}

pub fn calcBoundingSphere(self: *Self) void {
    var mesh_min = zmath.splat(zmath.Vec, std.math.inf(f32));
    var mesh_max = zmath.splat(zmath.Vec, -std.math.inf(f32));

    for (self.primitives) |*primitive| {
        var prim_min = zmath.splat(zmath.Vec, std.math.inf(f32));
        var prim_max = zmath.splat(zmath.Vec, -std.math.inf(f32));

        for (primitive.vertices) |vertex| {
            const pos = zmath.loadArr3(vertex.position);
            prim_min = zmath.min(prim_min, pos);
            prim_max = zmath.max(prim_max, pos);
        }

        primitive.sphere_pos_radius = computeBoundingSphere(prim_min, prim_max);

        mesh_min = zmath.min(mesh_min, prim_min);
        mesh_max = zmath.max(mesh_max, prim_max);
    }

    self.sphere_pos_radius = computeBoundingSphere(mesh_min, mesh_max);
}

fn computeBoundingSphere(min: zmath.Vec, max: zmath.Vec) [4]f32 {
    const center = (min + max) * zmath.splat(zmath.Vec, 0.5);
    const radius_vec = max - center;
    const radius = zmath.length3(radius_vec)[0];
    return .{ center[0], center[1], center[2], radius };
}
