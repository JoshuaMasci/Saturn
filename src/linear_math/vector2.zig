const std = @import("std");

pub fn Vector2Fn(comptime T: type) type {
    return struct {
        const Self = @This();
        const type_info = @typeInfo(T);

        data: std.meta.Vector(2, T),

        pub const zero = Self.new_value(0);
        pub const one = Self.new_value(1);
        pub const xaxis = Self.new(1, 0);
        pub const yaxis = Self.new(0, 1);

        pub fn new_value(v: T) Self {
            return Self.new(v, v);
        }

        pub fn new(x: T, y: T) Self {
            return Self{
                .data = [_]T{ x, y },
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
            return data[0] + data[1];
        }

        pub fn length(self: Self) T {
            return @sqrt(self.length2());
        }

        pub fn length2(self: Self) T {
            var data = self.data * self.data;
            return data[0] + data[1];
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
