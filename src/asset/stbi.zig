const std = @import("std");
const zstbi = @import("zstbi");
const Texture = @import("texture_2d.zig");

pub fn load(allocator: std.mem.Allocator, file_name: []const u8, file_buffer: []const u8) !Texture {
    zstbi.init(allocator);
    defer zstbi.deinit();

    var stb_image = try zstbi.Image.loadFromMemory(file_buffer, 0);
    defer stb_image.deinit();

    //RGB images should be forced to rgba
    if (stb_image.num_components == 3) {
        stb_image.deinit();
        stb_image = try zstbi.Image.loadFromMemory(file_buffer, 4);
    }

    const name = try allocator.dupe(u8, file_name);
    errdefer allocator.free(name);

    const data = try allocator.dupe(u8, stb_image.data);
    errdefer allocator.free(data);

    const format: Texture.Format = switch (stb_image.num_components) {
        1 => .r8,
        2 => .rg8,
        4 => .rgba8,
        else => return error.UnsupportedChannelCount,
    };

    return .{
        .name = name,
        .format = format,
        .width = stb_image.width,
        .height = stb_image.height,
        .data = data,
    };
}

pub fn loadFromFile(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !Texture {
    const file_buffer = try dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
    defer allocator.free(file_buffer);
    return load(allocator, std.fs.path.stem(file_path), file_buffer);
}
