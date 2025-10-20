const std = @import("std");

const AssetHandle = @import("../asset/registry.zig").Handle;
const Camera = @import("../rendering/camera.zig").Camera;
const RenderScene = @import("../rendering/scene.zig");
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
    var node: *const Node = &self.nodes[index];
    var transform: Transform = node.local_transform;

    while (node.parent) |parent| {
        node = &self.nodes[parent];
        transform = node.local_transform.applyTransform(&transform);
    }

    return transform;
}

pub fn loadScene(self: Self, render_scene: *RenderScene, root_transform: Transform) !void {
    for (self.root_nodes) |index| {
        try createRenderSceneNode(self.nodes, index, &root_transform, render_scene);
    }
}

fn createRenderSceneNode(nodes: []const Node, node_index: usize, parent_transform: *const Transform, render_scene: *RenderScene) !void {
    const node = &nodes[node_index];

    const transform = parent_transform.applyTransform(&node.local_transform);

    if (node.mesh) |mesh| {
        render_scene.addInstance(.{
            .transform = transform,
            .component = .{ .mesh = mesh.mesh, .materials = .fromSlice(mesh.materials) },
        });
    }

    for (node.children) |index| {
        try createRenderSceneNode(nodes, index, &transform, render_scene);
    }
}
