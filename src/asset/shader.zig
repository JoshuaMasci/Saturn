const std = @import("std");
const serde = @import("../serde.zig");

pub const Registry = @import("system.zig").AssetSystem(Self, &[_][]const u8{".shader"});

const MAGIC: [8]u8 = .{ 'S', 'A', 'T', '-', 'S', 'H', 'A', 'D' };

//TODO: maybe make this a flag (or something else) since it might be possible to have more than one stage with diffrent entry points (I.E. Vertex and Fragment Shader in the same stage)
const Stage = enum(u32) {
    vertex,
    fragment,
    compute,
};

const BindingCounts = struct {
    samplers: u32,
    storage_textures: u32,
    storage_buffers: u32,
    uniform_buffers: u32,
};

const Self = @This();

name: []u8,
//stage: Stage,
spirv_code: []u8,

//TODO: support other shader formats at some point
//dxil_code: []u8, //TODO: support dxbc?
//msl_code: []u8, //TODO: support metallib?

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    //allocator.free(self.spirv_code);
    //allocator.free(self.dxil_code);
    //allocator.free(self.msl_code);
}

pub fn serialize(self: Self, writer: anytype) !void {
    try writer.writeAll(&MAGIC);
    try serde.serialzieSlice(u8, writer, self.name);
    //try writer.writeInt(u32, @intFromEnum(self.stage), .little);
    try serde.serialzieSlice(u8, writer, self.spirv_code);
    //try serde.serialzieSlice(u8, writer, self.dxil_code);
    //try serde.serialzieSlice(u8, writer, self.msl_code);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: anytype) !Self {
    var magic: [8]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &MAGIC, &magic)) {
        return error.InvalidMagic;
    }

    const name = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(name);

    //const stage: Stage = @enumFromInt(try reader.readInt(u32, .little));

    const spirv_code = try serde.deserialzieSlice(allocator, u8, reader);
    errdefer allocator.free(spirv_code);

    // const dxil_code = try serde.deserialzieSlice(allocator, u8, reader);
    // errdefer allocator.free(dxil_code);

    // const msl_code = try serde.deserialzieSlice(allocator, u8, reader);
    // errdefer allocator.free(msl_code);

    return .{
        .name = name,
        //.stage = stage,
        .spirv_code = spirv_code,
        // .dxil_code = dxil_code,
        // .msl_code = msl_code,
    };
}
