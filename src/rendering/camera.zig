const std = @import("std");
const zm = @import("zmath");
const Transform = @import("../transform.zig");

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

    pub fn getPerspectiveMatrix(self: Self, aspect_ratio: f32) zm.Mat {
        return zm.perspectiveFovRhGl(self.fov.get_fov_y_rad(aspect_ratio), aspect_ratio, self.near, self.far);
    }
};

pub const Camera = union(enum) {
    const Self = @This();

    pub const Default: Self = .{ .perspective = .{} };
    perspective: PerspectiveCamera,

    pub fn getProjectionMatrix(self: Self, aspect_ratio: f32) zm.Mat {
        return self.perspective.getPerspectiveMatrix(aspect_ratio);
    }
};
