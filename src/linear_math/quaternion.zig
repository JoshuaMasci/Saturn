const std = @import("std");

pub const Vector3 = @import("linear_math/vector3.zig");

pub fn QuaternionFn(comptime T: type) type {
    if (@typeInfo(T) != .Float) {
        @compileError("Quaternion not implemented for " ++ @typeName(T) ++ " must use float type");
    }
    return struct {
        const Self = @This();
        const Vec3Type = Vector3.Vector3Fn(T);

        const W = 0;
        const X = 1;
        const Y = 2;
        const Z = 3;

        //W, X, Y, Z
        data: std.meta.Vector(4, T),

        pub const identity = Self{ .data = [_]T{ 1, 0, 0, 0 } };

        pub fn axisAngle(axis: Vec3Type, angle_rad: T) Self {
            var angle_2 = angle_rad * 0.5;
            var sin = Vec3Type.new_value(@sin(angle_2));
            var values = axis.normalize().mul(sin).data;

            return Self{
                .data = [_]T{ @cos(angle_2), values[0], values[1], values[2] },
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

        pub fn length(self: Self) T {
            return @sqrt(self.length2());
        }

        pub fn length2(self: Self) T {
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

        pub fn rotate(self: Self, vec: Vec3Type) Vec3Type {
            var u = Vec3Type.new(
                self.data[X],
                self.data[Y],
                self.data[Z],
            );
            var w = self.data[W];
            var uv = u.cross(vec);
            var uuv = u.cross(uv);
            var r = vec.add(uv.scale(w).add(uuv).scale(2));
            return r;
        }
    };
}
