const std = @import("std");
const serde = @import("../serde.zig");

const TextureAssetHandle = @import("texture_2d.zig").Registry.Handle;

pub const Registry = @import("system.zig").AssetSystem(Self, &[_][]const u8{".json_mat"});

const MAGIC: [8]u8 = .{ 'S', 'A', 'T', '-', 'M', 'A', 'T', 'E' };

pub const Json = struct {
    base_color_texture: ?[]const u8 = null,
    base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

    metallic_roughness_texture: ?[]const u8 = null,
    metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

    emissive_texture: ?[]const u8 = null,
    emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

    occlusion_texture: ?[]const u8 = null,
    normal_texture: ?[]const u8 = null,

    pub fn readFromJsonFile(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !std.json.Parsed(@This()) {
        const file_buffer = try dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null);
        defer allocator.free(file_buffer);
        return try std.json.parseFromSlice(@This(), allocator, file_buffer, .{ .allocate = .alloc_if_needed });
    }
};

const Self = @This();

base_color_texture: ?TextureAssetHandle = null,
base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

metallic_roughness_texture: ?TextureAssetHandle = null,
metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

emissive_texture: ?TextureAssetHandle = null,
emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

occlusion_texture: ?TextureAssetHandle = null,
normal_texture: ?TextureAssetHandle = null,

pub fn initFromJson(json: Json) Self {
    var base_color_texture: ?TextureAssetHandle = null;
    if (json.base_color_texture) |texture_string|
        base_color_texture = TextureAssetHandle.fromRepoPath(texture_string);

    var metallic_roughness_texture: ?TextureAssetHandle = null;
    if (json.metallic_roughness_texture) |texture_string|
        metallic_roughness_texture = TextureAssetHandle.fromRepoPath(texture_string);

    var emissive_texture: ?TextureAssetHandle = null;
    if (json.emissive_texture) |texture_string|
        emissive_texture = TextureAssetHandle.fromRepoPath(texture_string);

    var occlusion_texture: ?TextureAssetHandle = null;
    if (json.occlusion_texture) |texture_string|
        occlusion_texture = TextureAssetHandle.fromRepoPath(texture_string);

    var normal_texture: ?TextureAssetHandle = null;
    if (json.normal_texture) |texture_string|
        normal_texture = TextureAssetHandle.fromRepoPath(texture_string);

    return .{
        .base_color_texture = base_color_texture,
        .base_color_factor = json.base_color_factor,

        .metallic_roughness_texture = metallic_roughness_texture,
        .metallic_roughness_factor = json.metallic_roughness_factor,

        .emissive_texture = emissive_texture,
        .emissive_factor = json.emissive_factor,

        .occlusion_texture = occlusion_texture,
        .normal_texture = normal_texture,
    };
}

pub fn serialize(self: Self, writer: anytype) !void {
    try writer.writeAll(&MAGIC);
    try writer.writeStructEndian(self, .little);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype) !Self {
    _ = allocator; // autofix
    var magic: [8]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &MAGIC, &magic)) {
        return error.InvalidMagic;
    }
    return try reader.readStructEndian(Self, .little);
}
