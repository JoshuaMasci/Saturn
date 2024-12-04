const std = @import("std");
const za = @import("zalgebra");

const Transform = @import("transform.zig");

pub const Fov = union(enum) {
    x: f32,
    y: f32,

    pub fn get_fov_y_rad(self: @This(), aspect_ratio: f32) f32 {
        return switch (self) {
            .x => |fov_x| std.math.atan(std.math.tan(std.math.degreesToRadians(fov_x) / 2.0) / aspect_ratio) * 2.0,
            .y => |fov_y| std.math.degreesToRadians(fov_y),
        };
    }
};

test "camera.fov" {
    const aspect_ratio = 2.0;
    const fov_test1 = Fov{ .y = 45.0 };
    const fov_test2 = Fov{ .x = 75.0 };
    try std.testing.expectApproxEqRel(0.7853982, fov_test1.get_fov_y_rad(aspect_ratio), std.math.floatEps(f32));
    try std.testing.expectApproxEqRel(0.73268867, fov_test2.get_fov_y_rad(aspect_ratio), std.math.floatEps(f32));
}

pub const PerspectiveCamera = struct {
    const Self = @This();

    fov: Fov = .{ .y = 45.0 },
    near: f32 = 0.1,
    far: f32 = 1000.0,

    pub fn perspective_gl(self: Self, aspect_ratio: f32) za.Mat4 {
        return za.Mat4.RightHanded.Gl.perspective(self.fov.get_fov_y_rad(aspect_ratio), aspect_ratio, self.near, self.far);
    }
};

pub const Camera = struct {
    const Self = @This();

    data: PerspectiveCamera = .{},
    transform: Transform = .{},
};

pub const Camera2 = union(enum) {
    perspective: PerspectiveCamera,
};
