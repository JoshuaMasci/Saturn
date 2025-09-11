const std = @import("std");

const zm = @import("zmath");

const culling = @import("culling.zig");
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

    pub fn getFrustum(self: PerspectiveCamera, aspect_ratio: f32, transform: Transform) culling.Frustum {
        const fov_y = self.fov.get_fov_y_rad(aspect_ratio);
        const forward = transform.getForward();
        const right = transform.getRight();
        const up = transform.getUp();
        const position = transform.position;

        const tan_half_fov_y = @tan(fov_y / 2.0);
        const tan_half_fov_x = tan_half_fov_y * aspect_ratio;

        var plane_count: usize = 5;
        var planes: [6]culling.Plane = undefined;

        // Left Plane
        {
            const left_dir = zm.normalize3(forward * zm.f32x4s(1.0) - right * zm.f32x4s(tan_half_fov_x));
            planes[0] = .initPosNormal(position, zm.cross3(up, left_dir));
        }

        // Right Plane
        {
            const right_dir = zm.normalize3(forward * zm.f32x4s(1.0) + right * zm.f32x4s(tan_half_fov_x));
            planes[1] = .initPosNormal(position, zm.cross3(right_dir, up));
        }

        // Top Plane
        {
            const top_dir = zm.normalize3(forward * zm.f32x4s(1.0) + up * zm.f32x4s(tan_half_fov_y));
            planes[2] = .initPosNormal(position, zm.cross3(right, top_dir));
        }

        // Bottom Plane
        {
            const bottom_dir = zm.normalize3(forward * zm.f32x4s(1.0) - up * zm.f32x4s(tan_half_fov_y));
            planes[3] = .initPosNormal(position, zm.cross3(bottom_dir, right));
        }

        planes[4] = .initPosNormal(position + (forward * zm.f32x4s(self.near)), forward);

        if (self.far) |zfar| {
            planes[plane_count] = .initPosNormal(position + (forward * zm.f32x4s(zfar)), -forward);
            plane_count += 1;
        }

        return .{
            .plane_count = plane_count,
            .planes = planes,
        };
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

    pub fn getFrustum(self: Self, aspect_ratio: f32, transform: Transform) culling.Frustum {
        return switch (self) {
            .perspective => |perspective| perspective.getFrustum(aspect_ratio, transform),
            .orthographic => unreachable,
        };
    }
};
