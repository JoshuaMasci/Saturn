const std = @import("std");
const zstbi = @import("zstbi");
const Texture = @import("texture_2d.zig");

pub fn loadTexture2d(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !Texture {
    const file_buffer = try dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
    defer allocator.free(file_buffer);

    zstbi.init(allocator);
    defer zstbi.deinit();

    var stb_image = try zstbi.Image.loadFromMemory(file_buffer, 0);
    defer stb_image.deinit();

    const data = try allocator.alloc(u8, stb_image.data.len);
    errdefer allocator.free(data);
    @memcpy(data, stb_image.data);

    const format: Texture.Format = switch (stb_image.num_components) {
        1 => .r8,
        2 => .rg8,
        4 => .rgba8,
        else => return error.UnsupportedChannelCount,
    };

    return .{
        .format = format,
        .width = stb_image.width,
        .height = stb_image.height,
        .data = data,
    };
}
