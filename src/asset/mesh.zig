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

pub const Index = u32;

pub const Primitive = struct {
    sphere_pos_radius: [4]f32,
    vertex_offset: u32,
    vertex_count: u32,
    index_offset: u32,
    index_count: u32,
    meshlet_offset: u32,
    meshlet_count: u32,
};

pub const Meshlet = extern struct {
    sphere_pos_radius: [4]f32,
    vertex_offset: u32,
    vertex_count: u32,
    triangle_offset: u32,
    triangle_count: u32,
};

const Self = @This();

name: []const u8,
sphere_pos_radius: [4]f32,

vertices: []Vertex,
indices: []u32,
primitives: []Primitive,

meshlets: []Meshlet,
meshlet_vertices: []u32,
meshlet_triangles: []u8,

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);

    allocator.free(self.vertices);
    allocator.free(self.indices);
    allocator.free(self.primitives);

    allocator.free(self.meshlets);
    allocator.free(self.meshlet_vertices);
    allocator.free(self.meshlet_triangles);
}

pub fn serialize(self: Self, writer: anytype) !void {
    try serde.serialzieSlice(u8, writer, self.name);

    try writer.writeAll(&std.mem.toBytes(self.sphere_pos_radius));

    try serde.serialzieSlice(Vertex, writer, self.vertices);
    try serde.serialzieSlice(u32, writer, self.indices);
    try serde.serialzieSlice(Primitive, writer, self.primitives);

    try serde.serialzieSlice(Meshlet, writer, self.meshlets);
    try serde.serialzieSlice(u32, writer, self.meshlet_vertices);
    try serde.serialzieSlice(u8, writer, self.meshlet_triangles);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype) !Self {
    const name = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(name);

    var sphere_pos_radius: [4]f32 = undefined;
    _ = try reader.readAll(std.mem.asBytes(&sphere_pos_radius));

    const vertices = try serde.deserialzieSlice(allocator, Vertex, reader);
    errdefer allocator.free(vertices);

    const indices = try serde.deserialzieSlice(allocator, u32, reader);
    errdefer allocator.free(indices);

    const primitives = try serde.deserialzieSlice(allocator, Primitive, reader);
    errdefer allocator.free(primitives);

    const meshlets = try serde.deserialzieSlice(allocator, Meshlet, reader);
    errdefer allocator.free(meshlets);

    const meshlet_vertices = try serde.deserialzieSlice(allocator, u32, reader);
    errdefer allocator.free(meshlet_vertices);

    const meshlet_triangles = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(meshlet_triangles);

    return .{
        .name = name,
        .sphere_pos_radius = sphere_pos_radius,

        .vertices = vertices,
        .indices = indices,
        .primitives = primitives,

        .meshlets = meshlets,
        .meshlet_vertices = meshlet_vertices,
        .meshlet_triangles = meshlet_triangles,
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
