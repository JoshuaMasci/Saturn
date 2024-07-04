const std = @import("std");

pub fn init(allocator: std.mem.Allocator) void {
    _ = allocator; // autofix
}
pub fn deinit() void {}

// Shapes
pub const Shape = struct {
    pub fn init__sphere(radius: f32) void {
        _ = radius; // autofix
    }

    pub fn init_box(half_extent: [3]f32) void {
        _ = half_extent; // autofix
    }

    pub fn init_cylinder(
        half_height: f32,
        radius: f32,
    ) void {
        _ = half_height; // autofix
        _ = radius; // autofix
    }

    pub fn init_capsule(
        half_height: f32,
        radius: f32,
    ) void {
        _ = half_height; // autofix
        _ = radius; // autofix
    }

    pub fn deinit() void {}
};

// World
pub const World = struct {
    const Self = @This();

    pub fn init() void {}
    pub fn deinit() void {}

    pub fn update(self: *Self, delta_time: f32) void {
        _ = self; // autofix
        _ = delta_time; // autofix
    }

    pub fn add_body(self: *Self) void {
        _ = self; // autofix
    }
    pub fn remove_body(self: *Self) void {
        _ = self; // autofix
    }
};
