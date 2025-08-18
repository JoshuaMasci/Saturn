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
    fov: Fov = .{ .y = 45.0 },
    near: f32 = 0.1,
    far: ?f32 = null,

    pub fn getPerspectiveMatrix(self: PerspectiveCamera, aspect_ratio: f32) zm.Mat {
        //TODO: create infinte perspective matrix
        return zm.perspectiveFovRh(self.fov.get_fov_y_rad(aspect_ratio), aspect_ratio, self.near, self.far orelse 1000.0);
    }
};

pub const Size = union(enum) {
    width: f32,
    height: f32,

    pub fn getWidthHeight(self: @This(), aspect_ratio: f32) struct {
        width: f32,
        height: f32,
    } {
        return switch (self) {
            .width => |x| .{ .width = x, .height = x * aspect_ratio },
            .height => |y| .{ .width = y / aspect_ratio, .height = y },
        };
    }
};

pub const OrthographicCamera = struct {
    size: Size = .{ .width = 1.0 },
    near: f32 = 0.1,
    far: f32 = 1000.0,

    pub fn getPerspectiveMatrix(self: OrthographicCamera, aspect_ratio: f32) zm.Mat {
        const size = self.size.getWidthHeight(aspect_ratio);
        return zm.orthographicRh(size.width, size.height, self.near, self.far);
    }
};

pub const Camera = union(enum) {
    const Self = @This();

    perspective: PerspectiveCamera,
    orthographic: OrthographicCamera,

    pub const Default: Self = .{ .perspective = .{} };
    pub fn getProjectionMatrix(self: Self, aspect_ratio: f32) zm.Mat {
        return switch (self) {
            .perspective => |perspective| perspective.getPerspectiveMatrix(aspect_ratio),
            .orthographic => |orthographic| orthographic.getPerspectiveMatrix(aspect_ratio),
        };
    }
};
