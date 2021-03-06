const std = @import("std");

pub fn Vector3Fn(comptime T: type) type {
    return struct {
        const Self = @This();
        const type_info = @typeInfo(T);

        const X = 0;
        const Y = 1;
        const Z = 2;

        data: std.meta.Vector(3, T),

        pub const zero = Self.new_value(0);
        pub const one = Self.new_value(1);
        pub const xaxis = Self.new(1, 0, 0);
        pub const yaxis = Self.new(0, 1, 0);
        pub const zaxis = Self.new(0, 0, 1);

        pub fn new_value(v: T) Self {
            return Self.new(v, v, v);
        }

        pub fn new(x: T, y: T, z: T) Self {
            return Self{
                .data = .{ x, y, z },
            };
        }

        pub fn add(lhs: Self, rhs: Self) Self {
            return Self{
                .data = lhs.data + rhs.data,
            };
        }

        pub fn sub(lhs: Self, rhs: Self) Self {
            return Self{
                .data = lhs.data - rhs.data,
            };
        }

        pub fn mul(lhs: Self, rhs: Self) Self {
            return Self{
                .data = lhs.data * rhs.data,
            };
        }

        pub fn div(lhs: Self, rhs: Self) Self {
            return Self{
                .data = lhs.data / rhs.data,
            };
        }

        pub fn scale(self: Self, v: T) Self {
            return self.mul(Self.new_value(v));
        }

        pub fn dot(lhs: Self, rhs: Self) T {
            var data = lhs.data * rhs.data;
            return data[0] + data[1] + data[2];
        }

        pub fn cross(lhs: Self, rhs: Self) Self {
            //TODO: SIMD commands
            return Self{
                .data = .{
                    (lhs.data[Y] * rhs.data[Z]) - (lhs.data[Z] * rhs.data[Y]),
                    (lhs.data[Z] * rhs.data[X]) - (lhs.data[X] * rhs.data[Z]),
                    (lhs.data[X] * rhs.data[Y]) - (lhs.data[Y] * rhs.data[X]),
                },
            };
        }

        pub fn length(self: Self) T {
            return @sqrt(self.length2());
        }

        pub fn length2(self: Self) T {
            var data = self.data * self.data;
            return data[0] + data[1] + data[2];
        }

        pub fn normalize(self: Self) Self {
            return self.div(Self.new_value(self.length()));
        }

        pub fn abs(self: Self) Self {
            return Self{
                .data = @fabs(self.data),
            };
        }
    };
}
