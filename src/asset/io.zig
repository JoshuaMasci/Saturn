const std = @import("std");

const header_v1 = @import("header.zig");

pub fn writeFile(dir: std.fs.Dir, atype: header_v1.AssetType, path: []const u8, asset: anytype) !void {
    makePath(dir, path);
    const file = try dir.createFile(path, .{});
    defer file.close();

    const writer = file.writer();
    try writer.writeStruct(header_v1.HeaderV1{
        .atype = atype,
    });
    try asset.serialize(writer);
}

pub fn readFile(allocator: std.mem.Allocator, reader: std.fs.File.Reader, comptime T: type) !T {
    const header = try reader.readStruct(header_v1.HeaderV1);
    if (!header.validMagic()) {
        return error.InvalidMagic;
    }
    if (!header.validVersion()) {
        return error.InvalidVersion;
    }

    return try T.deserialzie(allocator, reader);
}

pub fn makePath(dir: std.fs.Dir, file_path: []const u8) void {
    if (std.fs.path.dirname(file_path)) |dir_path| {
        dir.makePath(dir_path) catch return;
    }
}
