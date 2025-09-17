const std = @import("std");

const serde = @import("../serde.zig");

pub const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    tangent: [4]f32,
    uv0: [2]f32,
    uv1: [2]f32,
};

pub const Meshlet = extern struct {
    sphere_pos_radius: [4]f32,
    vertex_offset: u32,
    vertex_count: u32,
    triangle_offset: u32,
    triangle_count: u32,
};

pub const Primitive = struct {
    sphere_pos_radius: [4]f32,
    vertex_offset: u32,
    vertex_count: u32,
    index_offset: u32,
    index_count: u32,
    meshlet_offset: u32,
    meshlet_count: u32,
};

name: []const u8,
sphere_pos_radius: [4]f32,

vertices: []Vertex,
indices: []u32,
meshlets: []Meshlet,
primitives: []Primitive,
meshlet_vertices: []u32,
meshlet_triangles: []u8,
