const std = @import("std");

pub fn FixedArrayList(comptime T: type, comptime N: comptime_int) type {
    return struct {
        const Self = @This();

        pub const empty: Self = .{ .items = undefined, .count = 0 };

        items: [N]T,
        count: usize,

        pub fn fromSlice(src: []const T) Self {
            std.debug.assert(src.len <= N);
            var items: [N]T = undefined;
            std.mem.copyForwards(T, &items, src);

            return .{
                .items = items,
                .count = src.len,
            };
        }

        pub fn add(self: *Self, item: T) void {
            std.debug.assert(self.count < N);
            self.items[self.count] = item;
            self.count += 1;
        }

        pub fn slice(self: *const Self) []const T {
            return self.items[0..self.count];
        }

        pub fn mutSlice(self: *Self) []T {
            return self.items[0..self.count];
        }
    };
}
