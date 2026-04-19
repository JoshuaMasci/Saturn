const std = @import("std");

const AssetHandle = @import("../asset/registry.zig").Handle;
const Camera = @import("../rendering/camera.zig").Camera;
const Transform = @import("../transform.zig");

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

pub fn serialize(self: Self, writer: *std.io.Writer) !void {
    try std.json.Stringify.value(self, .{ .whitespace = .indent_tab }, writer);
}

pub fn deserialzie(allocator: std.mem.Allocator, reader: *std.io.Reader) !std.json.Parsed(Self) {
    const data = try reader.allocRemaining(allocator, .unlimited);
    defer allocator.free(data);

    return try std.json.parseFromSlice(Self, allocator, data, .{ .allocate = .alloc_always });
}

pub const Node = struct {
    name: []const u8,
    local_transform: Transform,
    parent: ?usize,
    children: []const usize,
    mesh: ?Mesh,
    camera: ?Camera,
};

pub const Mesh = struct {
    mesh: AssetHandle,
    materials: []const AssetHandle,
};

pub fn getNodeFromName(self: Self, name: []const u8) ?usize {
    for (self.nodes, 0..) |node, i| {
        if (std.mem.eql(u8, node.name, name)) {
            return i;
        }
    }
    return null;
}

pub fn calcNodeGlobalTransform(self: Self, index: usize) Transform {
    var node: usize = index;
    var transform: Transform = self.nodes[node].local_transform;

    while (self.nodes[node].parent) |parent| {
        // detect loops, cause this is apparently a problem
        if (node == parent) break;
        node = parent;
        transform = self.nodes[node].local_transform.applyTransform(&transform);
    }

    return transform;
}
