const std = @import("std");

const serde = @import("../serde.zig");
const AssetHandle = @import("registry.zig").Handle;

pub const LoadSettings = struct {};

pub const AlphaMode = enum(u32) {
    @"opaque",
    mask,
    blend,
};

const Self = @This();

name: []const u8,

alpha_mode: AlphaMode = .@"opaque",
alpha_cutoff: f32 = 0.0,

base_color_texture: ?AssetHandle = null,
base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

metallic_roughness_texture: ?AssetHandle = null,
metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

emissive_texture: ?AssetHandle = null,
emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

occlusion_texture: ?AssetHandle = null,
normal_texture: ?AssetHandle = null,

pub fn initFromJson(allocator: std.mem.Allocator, json: *const Json) !Self {
    const name = try allocator.dupe(u8, json.name);

    var base_color_texture: ?AssetHandle = null;
    if (json.base_color_texture) |texture_string|
        base_color_texture = .fromRepoPathCombined(texture_string);

    var metallic_roughness_texture: ?AssetHandle = null;
    if (json.metallic_roughness_texture) |texture_string|
        metallic_roughness_texture = .fromRepoPathCombined(texture_string);

    var emissive_texture: ?AssetHandle = null;
    if (json.emissive_texture) |texture_string|
        emissive_texture = .fromRepoPathCombined(texture_string);

    var occlusion_texture: ?AssetHandle = null;
    if (json.occlusion_texture) |texture_string|
        occlusion_texture = .fromRepoPathCombined(texture_string);

    var normal_texture: ?AssetHandle = null;
    if (json.normal_texture) |texture_string|
        normal_texture = .fromRepoPathCombined(texture_string);

    return .{
        .name = name,

        .alpha_mode = json.alpha_mode,
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

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
}

pub fn dupe(self: *const Self, allocator: std.mem.Allocator) !Self {
    var new: Self = self.*;
    new.name = try allocator.dupe(u8, self.name);
    return new;
}

pub fn serialize(self: Self, writer: anytype) !void {
    try serde.serialzieSlice(u8, writer, self.name);
    try writer.writeStructEndian(Packed.pack(self), .little);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype, settings: LoadSettings) !Self {
    _ = settings; // autofix
    const name = try serde.deserialzieSlice(allocator, u8, reader);
    var value = (try reader.readStructEndian(Packed, .little)).unpack();
    value.name = name;

    return value;
}

//Json Material
pub const Json = struct {
    name: []const u8,
    alpha_mode: AlphaMode = .@"opaque",
    alpha_cutoff: f32 = 0.0,

    base_color_texture: ?[]const u8 = null,
    base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

    metallic_roughness_texture: ?[]const u8 = null,
    metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

    emissive_texture: ?[]const u8 = null,
    emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

    occlusion_texture: ?[]const u8 = null,
    normal_texture: ?[]const u8 = null,

    pub fn read(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !std.json.Parsed(Json) {
        const file_buffer = try dir.readFileAlloc(allocator, file_path, std.math.maxInt(usize));
        defer allocator.free(file_buffer);
        return try std.json.parseFromSlice(Json, allocator, file_buffer, .{ .allocate = .alloc_always });
    }

    pub fn write(self: @This(), allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) !void {
        const json_string = try std.json.stringifyAlloc(allocator, self, .{ .whitespace = .indent_tab });
        defer allocator.free(json_string);
        try dir.writeFile(.{
            .sub_path = file_path,
            .data = json_string,
        });
    }
};

// Gpu Material
pub const Gpu = extern struct {
    const ExpectedSize: usize = @sizeOf([4]f32) * 5;
    comptime {
        if (@sizeOf(Gpu) != ExpectedSize) {
            @compileError("Material.Gpu is incorrect size");
        }
    }

    // Block 1 (Vec4 size)
    alpha_mode: i32,
    alpha_cutoff: f32,
    base_color_texture: u32,
    metallic_roughness_texture: u32,

    // Block 2 (Vec4 size)
    emissive_texture: u32,
    occlusion_texture: u32,
    normal_texture: u32,
    pad0: i32 = 0,

    // Block 3 (3 * Vec4 size)
    base_color_factor: [4]f32,
    metallic_roughness_factor_pad2: [4]f32,
    emissive_factor_pad: [4]f32,

    pub fn pack(material: Self) Gpu {
        return .{
            .alpha_mode = @intCast(@intFromEnum(material.alpha_mode)),
            .alpha_cutoff = material.alpha_cutoff,
            .base_color_texture = 0,
            .metallic_roughness_texture = 0,

            .emissive_texture = 0,
            .occlusion_texture = 0,
            .normal_texture = 0,

            .base_color_factor = material.base_color_factor,
            .metallic_roughness_factor_pad2 = .{ material.metallic_roughness_factor[0], material.metallic_roughness_factor[1], 0.0, 0.0 },
            .emissive_factor_pad = .{ material.emissive_factor[0], material.emissive_factor[1], material.emissive_factor[2], 0.0 },
        };
    }
};

// Packed Material for asset system
const Packed = extern struct {
    alpha_mode: u32,
    alpha_cutoff: f32,

    has_base_color_texture: bool,
    base_color_texture: u64,
    base_color_factor: [4]f32,

    has_metallic_roughness_texture: bool,
    metallic_roughness_texture: u64,
    metallic_roughness_factor: [2]f32,

    has_emissive_texture: bool,
    emissive_texture: u64,
    emissive_factor: [3]f32,

    has_occlusion_texture: bool,
    occlusion_texture: u64,
    has_normal_texture: bool,
    normal_texture: u64,

    fn unwrapHandle(handle_opt: ?AssetHandle) u64 {
        if (handle_opt) |handle| {
            return handle.toU64();
        } else {
            return 0;
        }
    }

    pub fn pack(material: Self) Packed {
        return .{
            .alpha_mode = @intFromEnum(material.alpha_mode),
            .alpha_cutoff = material.alpha_cutoff,

            .has_base_color_texture = material.base_color_texture != null,
            .base_color_texture = unwrapHandle(material.base_color_texture),
            .base_color_factor = material.base_color_factor,

            .has_metallic_roughness_texture = material.metallic_roughness_texture != null,
            .metallic_roughness_texture = unwrapHandle(material.metallic_roughness_texture),
            .metallic_roughness_factor = material.metallic_roughness_factor,

            .has_emissive_texture = material.emissive_texture != null,
            .emissive_texture = unwrapHandle(material.emissive_texture),
            .emissive_factor = material.emissive_factor,

            .has_occlusion_texture = material.occlusion_texture != null,
            .occlusion_texture = unwrapHandle(material.occlusion_texture),
            .has_normal_texture = material.normal_texture != null,
            .normal_texture = unwrapHandle(material.normal_texture),
        };
    }

    pub fn unpack(material: *const Packed) Self {
        return .{
            .name = &.{},

            .alpha_mode = @enumFromInt(material.alpha_mode),
            .alpha_cutoff = material.alpha_cutoff,

            .base_color_texture = if (material.has_base_color_texture) AssetHandle.fromU64(material.base_color_texture) else null,
            .base_color_factor = material.base_color_factor,

            .metallic_roughness_texture = if (material.has_metallic_roughness_texture) AssetHandle.fromU64(material.metallic_roughness_texture) else null,
            .metallic_roughness_factor = material.metallic_roughness_factor,

            .emissive_texture = if (material.has_emissive_texture) AssetHandle.fromU64(material.emissive_texture) else null,
            .emissive_factor = material.emissive_factor,

            .occlusion_texture = if (material.has_occlusion_texture) AssetHandle.fromU64(material.occlusion_texture) else null,
            .normal_texture = if (material.has_normal_texture) AssetHandle.fromU64(material.normal_texture) else null,
        };
    }
};
