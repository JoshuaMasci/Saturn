const std = @import("std");

pub const Vector3 = @import("vector3.zig");
pub const Quaternion = @import("quaternion.zig");

pub fn Matrix4Fn(comptime T: type) type {
    if (@typeInfo(T) != .Float) {
        @compileError("Matrix4 not implemented for " ++ @typeName(T) ++ " must use float type");
    }
    return struct {
        const Self = @This();
        const Vec3Type = Vector3.Vector3Fn(T);
        const QuatType = Quaternion.QuaternionFn(T);

        data: [4]std.meta.Vector(4, T),

        pub const zero = Self{
            .data = .{
                .{ 0, 0, 0, 0 },
                .{ 0, 0, 0, 0 },
                .{ 0, 0, 0, 0 },
                .{ 0, 0, 0, 0 },
            },
        };

        pub const identity = Self{
            .data = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            },
        };

        pub fn translation(vec: Vec3Type) Self {
            return Self{
                .data = .{
                    .{ 1, 0, 0, 0 },
                    .{ 0, 1, 0, 0 },
                    .{ 0, 0, 1, 0 },
                    .{ vec.data[0], vec.data[1], vec.data[2], 1 },
                },
            };
        }

        pub fn rotation(quat: QuatType) Self {
            var data = quat.data;
            var qxx = data[1] * data[1];
            var qyy = data[2] * data[2];
            var qzz = data[3] * data[3];
            var qxz = data[1] * data[3];
            var qxy = data[1] * data[2];
            var qyz = data[2] * data[3];
            var qwx = data[0] * data[1];
            var qwy = data[0] * data[2];
            var qwz = data[0] * data[3];

            var result = Self.identity;

            //TODO: transpose this?
            result.data[0][0] = 1 - 2 * (qyy + qzz);
            result.data[0][1] = 2 * (qxy + qwz);
            result.data[0][2] = 2 * (qxz - qwy);

            result.data[1][0] = 2 * (qxy - qwz);
            result.data[1][1] = 1 - 2 * (qxx + qzz);
            result.data[1][2] = 2 * (qyz + qwx);

            result.data[2][0] = 2 * (qxz + qwy);
            result.data[2][1] = 2 * (qyz - qwx);
            result.data[2][2] = 1 - 2 * (qxx + qyy);

            return result;
        }

        pub fn scale(vec: Vec3Type) Self {
            return Self{
                .data = .{
                    .{ vec.data[0], 0, 0, 0 },
                    .{ 0, vec.data[1], 0, 0 },
                    .{ 0, 0, vec.data[2], 0 },
                    .{ 0, 0, 0, 1 },
                },
            };
        }

        pub fn model(p: Vec3Type, r: QuatType, s: Vec3Type) Self {
            return Self.translation(p).mul(Self.rotation(r)).mul(Self.scale(s));
        }

        pub fn orthographic_lh_zo(left: T, right: T, bottom: T, top: T, near: T, far: T) Self {
            return Self{
                .data = .{
                    .{ 2 / (right - left), 0, 0, 0 },
                    .{ 0, 2 / (top - bottom), 0, 0 },
                    .{ 0, 0, 1 / (far - near), 0 },
                    .{
                        -(right + left) / (right - left),
                        -(top + bottom) / (top - bottom),
                        -near / (far - near),
                        1,
                    },
                },
            };
        }

        pub fn perspective_lh_zo(fovy: T, aspect_ratio: T, near: T, far: T) Self {
            var tan_half_fov = std.math.tan(fovy / 2);
            return Self{
                .data = .{
                    .{ 1 / (aspect_ratio * tan_half_fov), 0, 0, 0 },
                    .{ 0, 1 / tan_half_fov, 0, 0 },
                    .{ 0, 0, far / (far - near), 1 },
                    .{ 0, 0, -(far * near) / (far - near), 1 },
                },
            };
        }

        pub fn view_lh(pos: Vec3Type, rot: QuatType) Self {
            var r = rot.rotate(Vec3Type.xaxis).normalize();
            var u = rot.rotate(Vec3Type.yaxis).normalize();
            var f = rot.rotate(Vec3Type.zaxis).normalize();
            return Self{
                .data = .{
                    .{ r.data[0], u.data[0], f.data[0], 0 },
                    .{ r.data[1], u.data[1], f.data[1], 0 },
                    .{ r.data[2], u.data[2], f.data[2], 0 },
                    .{ -r.dot(pos), -u.dot(pos), -f.dot(pos), 1 },
                },
            };
        }

        pub fn transpose(mat: Self) Self {
            var m = mat.data;
            return Self{
                .data = .{
                    .{ m[0][0], m[1][0], m[2][0], m[3][0] },
                    .{ m[0][1], m[1][1], m[2][1], m[3][1] },
                    .{ m[0][2], m[1][2], m[2][2], m[3][2] },
                    .{ m[0][3], m[1][3], m[2][3], m[3][3] },
                },
            };
        }

        pub fn mul(left: Self, right: Self) Self {
            var mat = Self.zero;
            var columns: usize = 0;
            while (columns < 4) : (columns += 1) {
                var rows: usize = 0;
                while (rows < 4) : (rows += 1) {
                    var sum: T = 0.0;
                    var current_mat: usize = 0;
                    while (current_mat < 4) : (current_mat += 1) {
                        sum += left.data[current_mat][rows] * right.data[columns][current_mat];
                    }
                    mat.data[columns][rows] = sum;
                }
            }

            return mat;
            //TODO: fix this
            // var lhs = self.data;
            // var rhs = other.transpose().data;

            // var result = Self.zero;
            // var row: u8 = 0;
            // while (row < 4) : (row += 1) {
            //     var column: u8 = 0;
            //     while (column < 4) : (column += 1) {
            //         //Force to product to slice
            //         var products: [4]f32 = lhs[row] * rhs[column];
            //         //TODO: unroll or use SIMD?
            //         for (products) |value| {
            //             result.data[row][column] += value;
            //         }
            //     }
            // }
            // return result;
        }
    };
}

//TODO: Make tests for these?
// var identity = Matrix4.identity;
// var scale = Matrix4.scale(Vector3.new(1, 2, 3));
// var translation = Matrix4.translation(Vector3.new(1, 2, 3));
// var rotation = Matrix4.rotation(Quaternion.axisAngle(Vector3.yaxis, 3.1415926 / 4.0));
// var multiply = translation.mul(scale).mul(rotation);

// std.log.info("Identity   : {d:0.2}", .{identity.data});
// std.log.info("scale      : {d:0.2}", .{scale.data});
// std.log.info("translation: {d:0.2}", .{translation.data});
// std.log.info("rotation   : {d:0.2}", .{rotation.data});
// std.log.info("multiply   : {d:0.2}", .{multiply.data});
