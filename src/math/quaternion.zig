const std = @import("std");

const vec3 = @import("vector3.zig");

pub fn quaternion(comptime T: type) type {
    if (@typeInfo(T) != .Float) {
        @compileError("Quaternion not implemented for " ++ @typeName(T));
    }
    return struct {
        const Self = @This();

        const W = 0;
        const X = 1;
        const Y = 2;
        const Z = 3;

        //W, X, Y, Z
        data: std.meta.Vector(4, T),

        pub const identity = Self{ .data = [_]T{ 1, 0, 0, 0 } };

        pub fn axis_angle(axis: vec3.vector3(T), angle_rad: T) Self {
            var angle_2 = angle_rad * 0.5;
            var sin = vec3.vector3(T).new_value(@sin(angle_2));
            var values = axis.normalize().mul(sin).data;

            return Self{
                .data = [_]T{ @cos(angle_rad), values[0], values[1], values[2] },
            };
        }

        pub fn inverse(self: *Self) Self {
            var len2 = self.length2();
            var inv_len2 = 1 / len2;
            var inv_data: std.meta.Vector(4, T) = [_]T{ inv_len2, inv_len2, inv_len2, inv_len2 };
            var neg_data: std.meta.Vector(4, T) = [_]T{ -1, -1, -1, 1 };
            return (self.data * neg_data) * inv_data;
        }

        pub fn normalize(self: *Self) Self {
            var len = self.length();
            return self.data / [_]T{ len, len, len, len };
        }

        pub fn length(self: *Self) T {
            return @sqrt(self.length2());
        }

        pub fn length2(self: *Self) T {
            var data = self.data * self.data;
            return data[W] +
                data[X] +
                data[Y] +
                data[Z];
        }

        pub fn mul(lhs: Self, rhs: Self) Self {
            var l = lhs.data;
            var r = rhs.data;

            return Self{
                .data = [_]T{
                    (l[W] * r[W]) - (l[X] * r[X]) - (l[Y] * r[Y]) - (l[Z] * r[Z]),
                    (l[W] * r[X]) + (l[X] * r[W]) + (l[Y] * r[Z]) - (l[Z] * r[Y]),
                    (l[W] * r[Y]) + (l[Y] * r[X]) + (l[Z] * r[X]) - (l[X] * r[Z]),
                    (l[W] * r[Z]) + (l[Z] * r[W]) + (l[X] * r[Y]) - (l[Y] * r[X]),
                },
            };
        }
    };
}
