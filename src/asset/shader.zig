const std = @import("std");
const serde = @import("../serde.zig");

pub const Registry = @import("system.zig").AssetSystem(Self, &[_][]const u8{".shader"});

const MAGIC: [8]u8 = .{ 'S', 'A', 'T', '-', 'S', 'H', 'A', 'D' };

pub const Stage = enum(u32) {
    vertex,
    fragment,
    compute,
};

const Bindings = struct {
    samplers: u32,
    storage_textures: u32,
    storage_buffers: u32,
    uniform_buffers: u32,
};

const Self = @This();

name: []const u8,
stage: Stage,
bindings: Bindings,
spirv_code: []const u8,

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    allocator.free(self.spirv_code);
}

pub fn serialize(self: Self, writer: anytype) !void {
    try writer.writeAll(&MAGIC);
    try serde.serialzieSlice(u8, writer, self.name);

    try writer.writeInt(u32, @intFromEnum(self.stage), .little);

    try writer.writeInt(u32, self.bindings.samplers, .little);
    try writer.writeInt(u32, self.bindings.storage_textures, .little);
    try writer.writeInt(u32, self.bindings.storage_buffers, .little);
    try writer.writeInt(u32, self.bindings.uniform_buffers, .little);

    try serde.serialzieSlice(u8, writer, self.spirv_code);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype) !Self {
    var magic: [8]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &MAGIC, &magic)) {
        return error.InvalidMagic;
    }

    const name = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(name);

    const stage: Stage = @enumFromInt(try reader.readInt(u32, .little));

    const samplers = try reader.readInt(u32, .little);
    const storage_textures = try reader.readInt(u32, .little);
    const storage_buffers = try reader.readInt(u32, .little);
    const uniform_buffers = try reader.readInt(u32, .little);
    const bindings: Bindings = .{ .samplers = samplers, .storage_textures = storage_textures, .storage_buffers = storage_buffers, .uniform_buffers = uniform_buffers };

    const spirv_code = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(spirv_code);

    return .{
        .name = name,
        .stage = stage,
        .bindings = bindings,
        .spirv_code = spirv_code,
    };
}
