const std = @import("std");
const serde = @import("../serde.zig");

const MAGIC: [8]u8 = .{ 'S', 'A', 'T', '-', 'T', 'E', 'X', '2' };

pub const Format = enum(u32) {
    r8,
    rg8,
    rgba8,
};

pub const ColorSpace = enum(u32) {
    linear,
    srgb,
};

const Self = @This();

format: Format,
color_space: ColorSpace = .linear,
width: u32,
height: u32,
data: []u8,
//TODO: mip data

pub fn serialize(self: Self, writer: anytype) !void {
    try writer.writeAll(&MAGIC);

    try writer.writeInt(u32, @intFromEnum(self.format), .little);
    try writer.writeInt(u32, @intFromEnum(self.color_space), .little);
    try writer.writeInt(u32, self.width, .little);
    try writer.writeInt(u32, self.height, .little);
    try serde.serialzieSlice(u8, writer, self.data);
}

pub fn deserialzie(reader: anytype, allocator: std.mem.Allocator) !Self {
    var magic: [8]u8 = undefined;
    try reader.readNoEof(&magic);
    if (std.mem.eql(u8, &MAGIC, &magic)) {
        return error.InvalidMagic;
    }

    _ = allocator; // autofix
}
