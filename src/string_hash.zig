const std = @import("std");

const Self = @This();
pub const HashType = u32;

hash: HashType,
string: []const u8,

pub fn new(comptime string: []const u8) Self {
    return .{
        .hash = std.hash.Fnv1a_32.hash(string),
        .string = string,
    };
}
