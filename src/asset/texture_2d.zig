const std = @import("std");
const serde = @import("../serde.zig");

pub const Registry = @import("system.zig").AssetSystem(Self, &[_][]const u8{".tex2d"});

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

pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    allocator.free(self.data);
}

pub fn serialize(self: Self, writer: anytype) !void {
    try writer.writeAll(&MAGIC);
    try writer.writeInt(u32, @intFromEnum(self.format), .little);
    try writer.writeInt(u32, @intFromEnum(self.color_space), .little);
    try writer.writeInt(u32, self.width, .little);
    try writer.writeInt(u32, self.height, .little);
    try serde.serialzieSlice(u8, writer, self.data);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype) !Self {
    var magic: [8]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &MAGIC, &magic)) {
        return error.InvalidMagic;
    }

    const format: Format = @enumFromInt(try reader.readInt(u32, .little));
    const color_space: ColorSpace = @enumFromInt(try reader.readInt(u32, .little));
    const width = try reader.readInt(u32, .little);
    const height = try reader.readInt(u32, .little);
    const data = try serde.deserialzieSlice(allocator, u8, reader);

    return .{
        .format = format,
        .color_space = color_space,
        .width = width,
        .height = height,
        .data = data,
    };
}
