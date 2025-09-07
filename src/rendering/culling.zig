const std = @import("std");

const zm = @import("zmath");
const Transform = @import("../transform.zig");

pub const Sphere = struct {
    const Self = @This();

    pos_radius: zm.Vec,

    pub fn initWorld(pos_radius: zm.Vec, tranform: *const Transform) Self {
        return calcWorldSpace(.{ .pos_radius = pos_radius }, tranform);
    }

    pub fn intersectsPlane(self: Self, plane: Plane) bool {
        return plane.distanceTo(self.pos_radius) > -self.pos_radius[3];
    }

    pub fn calcWorldSpace(self: Self, tranform: *const Transform) Self {
        const world_center = tranform.transformPoint(self.pos_radius);

        const max_scale = @max(@max(tranform.scale[0], tranform.scale[1]), tranform.scale[2]);
        const world_radius = self.pos_radius[3] * max_scale;
        return .{
            .pos_radius = .{ world_center[0], world_center[1], world_center[2], world_radius },
        };
    }
};

pub const AABB = struct {
    min: zm.Vec,
    max: zm.Vec,
};

pub const Plane = struct {
    normal_distance: zm.Vec,

    pub fn initNormlized(plane: zm.Vec) @This() {
        return .{
            .normal_distance = plane / zm.splat(zm.Vec, zm.length3(plane)[0]),
        };
    }

    pub fn initPosNormal(pos: zm.Vec, normal: zm.Vec) @This() {
        return .{
            .normal_distance = .{ normal[0], normal[1], normal[2], zm.dot3(pos, normal)[0] },
        };
    }

    pub fn distanceTo(self: @This(), point: zm.Vec) f32 {
        return zm.dot3(self.normal_distance, point)[0] - self.normal_distance[3];
    }
};

pub const Frustum = struct {
    plane_count: usize,
    planes: [6]Plane,

    pub fn fromViewProjectionMatrix(view_projection_matrix: zm.Mat) @This() {
        const row0 = view_projection_matrix[0];
        const row1 = view_projection_matrix[1];
        const row2 = view_projection_matrix[2];
        const row3 = view_projection_matrix[3];

        return .{
            .plane_count = 4,
            .planes = .{
                .initNormlized(row3 + row0), // Left
                .initNormlized(row3 - row0), // Right
                .initNormlized(row3 + row1), // Bottom
                .initNormlized(row3 - row1), // Top
                .initNormlized(row2), // Near
                .initNormlized(row3 - row2), // Far
            },
        };
    }

    pub fn intersects(self: @This(), comptime T: type, shape: T) bool {
        comptime if (!std.meta.hasFn(T, "intersectsPlane")) {
            @compileError("Frustum::intersects T requires intersectsPlane function");
        };

        for (self.planes[0..self.plane_count]) |plane| {
            if (!shape.intersectsPlane(plane)) {
                return false;
            }
        }
        return true;
    }
};

pub const Frustum2 = struct {
    left: Plane,
    right: Plane,

    up: Plane,
    down: Plane,

    far: ?Plane,
    near: Plane,
};
