const std = @import("std");

const physics = @import("physics");
const Mesh = @import("mesh.zig");

const c = @import("../../platform/sdl3.zig").c;
const Device = @import("device.zig");
const Window = @import("../../platform/sdl3.zig").Window;

const Self = @This();

gpu_device: Device,

color_format: c.SDL_GPUTextureFormat,
depth_format: c.SDL_GPUTextureFormat,

meshes: std.AutoArrayHashMap(physics.MeshPrimitive, Mesh),

pub fn init(
    allocator: std.mem.Allocator,
    gpu_device: Device,
    formats: struct {
        color: c.SDL_GPUTextureFormat,
        depth: c.SDL_GPUTextureFormat,
    },
) Self {
    return .{
        .gpu_device = gpu_device,
        .color_format = formats.color,
        .depth_format = formats.depth,
        .meshes = std.AutoArrayHashMap(physics.MeshPrimitive, Mesh).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    for (self.meshes.values()) |mesh| {
        mesh.deinit();
    }
    self.meshes.deinit();
}

pub fn buildFrame(self: Self, world: *physics.World, camera_transform: physics.Transform) void {
    _ = self; // autofix
    physics.debugRendererBuildFrame(world, camera_transform);
}

pub fn getDebugRendererData(self: *Self) physics.DebugRendererCallbacks {
    return .{
        .ptr = self,
        .draw_line = drawLineCallback,
        .draw_triangle = drawTriangleCallback,
        .draw_text = drawText3DCallback,
        .create_triangle_mesh = createTriangleMeshCallback,
        .create_indexed_mesh = createIndexedMeshCallback,
        .draw_geometry = drawGeometryCallback,
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
    //std.log.info("drawGeometryCallback", .{});
}

fn freeMeshPrimitive(ptr: ?*anyopaque, id: physics.MeshPrimitive) callconv(.C) void {
    _ = ptr; // autofix
    _ = id; // autofix
    std.log.info("freeMeshPrimitive", .{});
}
