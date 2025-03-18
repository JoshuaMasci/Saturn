const std = @import("std");

const physics = @import("physics");

const Self = @This();

pub fn getDebugRendererData(self: *Self) physics.DebugRendererData {
    _ = self; // autofix
    return .{
        .ptr = null,
        .draw_line = drawLineCallback,
        .draw_triangle = drawTriangleCallback,
        .draw_text = drawText3DCallback,
        .create_triangle_mesh = createTriangleMeshCallback,
        .create_indexed_mesh = createIndexedMeshCallback,
        .free_mesh = freeMeshPrimitive,
    };
}

fn drawLineCallback(ptr: ?*anyopaque, data: physics.DrawLineData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    std.log.info("drawLineCallback", .{});
}

fn drawTriangleCallback(ptr: ?*anyopaque, data: physics.DrawTriangleData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    std.log.info("drawTriangleCallback", .{});
}

fn drawText3DCallback(ptr: ?*anyopaque, data: physics.DrawTextData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    std.log.info("drawText3DCallback", .{});
}

fn createTriangleMeshCallback(ptr: ?*anyopaque, id: physics.MeshPrimitive, triangles: [*c]const physics.Triangle, triangle_count: usize) callconv(.C) void {
    _ = ptr; // autofix
    _ = id; // autofix
    _ = triangles; // autofix
    _ = triangle_count; // autofix
    std.log.info("createTriangleMeshCallback", .{});
}

fn createIndexedMeshCallback(ptr: ?*anyopaque, id: physics.MeshPrimitive, verties: [*c]const physics.Vertex, vertex_count: usize, indices: [*c]const u32, index_count: usize) callconv(.C) void {
    _ = ptr; // autofix
    _ = id; // autofix
    _ = verties; // autofix
    _ = vertex_count; // autofix
    _ = indices; // autofix
    _ = index_count; // autofix
    std.log.info("createIndexedMeshCallback", .{});
}

fn drawGeometryCallback(ptr: ?*anyopaque, data: physics.DrawGeometryData) callconv(.C) void {
    _ = ptr; // autofix
    _ = data; // autofix
    std.log.info("drawGeometryCallback", .{});
}

fn freeMeshPrimitive(ptr: ?*anyopaque, id: physics.MeshPrimitive) callconv(.C) void {
    _ = ptr; // autofix
    _ = id; // autofix
    std.log.info("freeMeshPrimitive", .{});
}
