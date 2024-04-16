const std = @import("std");
const zm = @import("zmath");

const Transform = @import("transform.zig");

pub const Fov = union(enum) {
    x: f32,
    y: f32,
};

pub const PerspectiveCamera = struct {
    const Self = @This();

    fov: Fov,
    near: f32,
    far: f32,

    pub const Default: Self = .{ .fov = .{ .x = 75.0 }, .near = 0.1, .far = 1000.0 };

    pub fn perspective_gl(self: Self, aspect_ratio: f32) zm.Mat {
        const fov = switch (self.fov) {
            .x => |fov_x| std.math.atan(std.math.tan(std.math.degreesToRadians(fov_x) / 2.0) * aspect_ratio) * 2.0,
            .y => |fov_y| std.math.degreesToRadians(fov_y),
        };
        return zm.perspectiveFovRhGl(fov, aspect_ratio, self.near, self.far);
    }
};

pub const Camera = struct {
    const Self = @This();

    data: PerspectiveCamera,
    transform: Transform,
};
