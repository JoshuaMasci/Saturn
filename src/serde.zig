const std = @import("std");

pub fn serialzieSlice(comptime T: type, writer: anytype, slice: []const T) !void {
    try writer.writeInt(u32, @intCast(slice.len), .little); // write length of the array
    const u8_slice: []const u8 = std.mem.sliceAsBytes(slice);
    try writer.writeAll(u8_slice);
}

pub fn deserialzieSlice(comptime T: type, reader: anytype, allocator: std.mem.Allocator) ![]T {
    const len = try reader.readInt(u32, .little);
    const slice = try allocator.alloc(T, len);
    const u8_slice: []u8 = std.mem.sliceAsBytes(slice);
    try reader.readNoEof(u8_slice);
    return slice;
}
