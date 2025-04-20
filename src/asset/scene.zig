const std = @import("std");

const Transform = @import("../transform.zig");
const MeshHandle = @import("mesh.zig").Registry.Handle;
const MaterialHandle = @import("material.zig").Registry.Handle;

const Self = @This();

name: []const u8,
root_nodes: []const usize,
nodes: []const Node,

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    allocator.free(self.root_nodes);

    for (self.nodes) |node| {
        allocator.free(node.name);
        allocator.free(node.children);
        if (node.mesh) |mesh| {
            allocator.free(mesh.materials);
        }
    }

    allocator.free(self.nodes);
}

pub fn serialize(self: Self, writer: anytype) !void {
    try std.json.stringify(self, .{ .whitespace = .indent_tab }, writer);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: std.fs.File.Reader) !std.json.Parsed(Self) {
    const data = try reader.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    return try std.json.parseFromSlice(Self, allocator, data, .{ .allocate = .alloc_always });
}

pub const Node = struct {
    name: []const u8,
    local_transform: Transform = .{},
    children: []const usize,
    mesh: ?Mesh = null,
};

pub const Mesh = struct {
    mesh: MeshHandle,
    materials: []const MaterialHandle,
};
