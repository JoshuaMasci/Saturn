const std = @import("std");

// No need for child types, the @inclue will be the StringHash struct
// Use it like the following: const StringHash = @import("string_hash.zig");

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
