const std = @import("std");

const serde = @import("../serde.zig");

pub const LoadSettings = struct {};

pub const TextureType = enum(u32) {
    @"2d",
    cube,
};

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

name: []const u8,
tex_type: TextureType,
format: Format,
color_space: ColorSpace = .linear,
width: u32,
height: u32,
depth: u32,
data: []const u8,

pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    allocator.free(self.data);
}

pub fn serialize(self: Self, writer: anytype) !void {
    try serde.serialzieSlice(u8, writer, self.name);
    try writer.writeInt(u32, @intFromEnum(self.tex_type), .little);
    try writer.writeInt(u32, @intFromEnum(self.format), .little);
    try writer.writeInt(u32, @intFromEnum(self.color_space), .little);
    try writer.writeInt(u32, self.width, .little);
    try writer.writeInt(u32, self.height, .little);
    try writer.writeInt(u32, self.depth, .little);
    try serde.serialzieSlice(u8, writer, self.data);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype, settings: LoadSettings) !Self {
    _ = settings; // autofix
    const name = try serde.deserialzieSlice(allocator, u8, reader);
    const tex_type: TextureType = @enumFromInt(try reader.readInt(u32, .little));
    const format: Format = @enumFromInt(try reader.readInt(u32, .little));
    const color_space: ColorSpace = @enumFromInt(try reader.readInt(u32, .little));
    const width = try reader.readInt(u32, .little);
    const height = try reader.readInt(u32, .little);
    const depth = try reader.readInt(u32, .little);
    const data = try serde.deserialzieSlice(allocator, u8, reader);

    return .{
        .name = name,
        .tex_type = tex_type,
        .format = format,
        .color_space = color_space,
        .width = width,
        .height = height,
        .depth = depth,
        .data = data,
    };
}
