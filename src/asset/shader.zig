const std = @import("std");

const serde = @import("../serde.zig");

pub const LoadSettings = struct {};

pub const DirectoryMeta = struct {
    language: Language = .glsl,
    target: Target = .vulkan,
    target_profile: []const u8,
    include_directories: []const []const u8,
};

pub const Meta = struct {
    target: Target = .vulkan,
    entry: ?[]const u8 = null,
};

pub const Language = enum(u32) {
    hlsl,
    glsl,
};

pub const Target = enum(u32) {
    vulkan,
};

pub const Stage = enum(u32) {
    vertex,
    fragment,
    compute,
    task,
    mesh,

    pub fn getShaderStage(ext: []const u8) ?Stage {
        if (std.mem.eql(u8, ext, ".vert")) {
            return .vertex;
        } else if (std.mem.eql(u8, ext, ".frag")) {
            return .fragment;
        } else if (std.mem.eql(u8, ext, ".comp")) {
            return .compute;
        } else if (std.mem.eql(u8, ext, ".task")) {
            return .task;
        } else if (std.mem.eql(u8, ext, ".mesh")) {
            return .mesh;
        } else {
            return null;
        }
    }
};

const Bindings = struct {
    samplers: u32 = 0,
    storage_textures: u32 = 0,
    storage_buffers: u32 = 0,
    uniform_buffers: u32 = 0,
};

const Self = @This();

name: []const u8,
target: Target,
stage: Stage,
bindings: Bindings,
spirv_code: []const u32,

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    allocator.free(self.spirv_code);
}

pub fn serialize(self: Self, writer: anytype) !void {
    try serde.serialzieSlice(u8, writer, self.name);

    try writer.writeInt(u32, @intFromEnum(self.target), .little);
    try writer.writeInt(u32, @intFromEnum(self.stage), .little);

    try writer.writeInt(u32, self.bindings.samplers, .little);
    try writer.writeInt(u32, self.bindings.storage_textures, .little);
    try writer.writeInt(u32, self.bindings.storage_buffers, .little);
    try writer.writeInt(u32, self.bindings.uniform_buffers, .little);

    try serde.serialzieSlice(u32, writer, self.spirv_code);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype, settings: LoadSettings) !Self {
    _ = settings; // autofix
    const name = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(name);

    const target: Target = @enumFromInt(try reader.readInt(u32, .little));
    const stage: Stage = @enumFromInt(try reader.readInt(u32, .little));

    const samplers = try reader.readInt(u32, .little);
    const storage_textures = try reader.readInt(u32, .little);
    const storage_buffers = try reader.readInt(u32, .little);
    const uniform_buffers = try reader.readInt(u32, .little);
    const bindings: Bindings = .{ .samplers = samplers, .storage_textures = storage_textures, .storage_buffers = storage_buffers, .uniform_buffers = uniform_buffers };

    const spirv_code = try serde.deserialzieSlice(allocator, u32, reader);
    errdefer allocator.free(spirv_code);

    return .{
        .name = name,
        .target = target,
        .stage = stage,
        .bindings = bindings,
        .spirv_code = spirv_code,
    };
}
