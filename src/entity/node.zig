const std = @import("std");
const Transform = @import("../transform.zig");
const ObjectPool = @import("../containers.zig").HandlePool;

pub const Components = @import("node_components.zig");

const Self = @This();

pub const Pool = ObjectPool(Self);
pub const Handle = Pool.Handle;

handle: Handle,

local_transform: Transform = .{},
components: Components,

parent: ?Handle = null,
childen: ChildList = ChildList{},

pub fn deinit(self: *Self) void {
    self.components.deinit();
}

pub const ChildList = std.BoundedArray(Handle, 16);

pub const Nodes = struct {
    allocator: std.mem.Allocator,
    root_nodes: ChildList,
    pool: Pool,

    pub fn init(allocator: std.mem.Allocator) Nodes {
        return .{
            .allocator = allocator,
            .root_nodes = ChildList{},
            .pool = Pool.init(allocator),
        };
    }

    pub fn deinit(self: *Nodes) void {
        self.pool.deinit_with_entries();
    }

    pub fn addNode(
        self: *Nodes,
        parent: ?Handle,
        local_transform: Transform,
    ) *Self {
        const handle = self.pool.insert(.{
            .parent = parent,
            .handle = undefined,
            .local_transform = local_transform,
            .components = Components.init(self.allocator),
        }) catch |err| std.debug.panic("Failed to create node: {}", .{err});
        self.pool.getPtr(handle).?.handle = handle;

        if (parent) |parent_handle| {
            if (self.pool.getPtr(parent_handle)) |parent_node| {
                parent_node.childen.append(handle) catch |err| std.debug.panic("Failed to add to child list: {}", .{err});
            } else {
                std.log.err("Invalid parent handle ({})", .{parent_handle});
            }
        } else {
            self.root_nodes.append(handle) catch |err| std.debug.panic("Failed to add to root list: {}", .{err});
        }

        return self.pool.getPtr(handle).?;
    }

    pub fn removeNode(self: *Nodes, node_handle: Handle) void {
        if (self.pool.remove(node_handle)) |node| {
            for (node.childen.slice()) |child_handle| {
                self.remove_node(child_handle);
            }

            if (node.parent) |parent_handle| {
                if (self.pool.getPtr(parent_handle)) |parent| {
                    _ = removeFromList(&parent.childen, node_handle);
                } else {
                    std.log.err("Node({}) had an invalid Parent({})", .{ node_handle, parent_handle });
                }
            } else {
                _ = removeFromList(&self.root_nodes, node_handle);
            }

            node.deinit();
        }
    }

    pub fn getNodeRootTransform(self: Nodes, node_handle: Handle) ?Transform {
        const node = self.pool.get(node_handle).?;
        var parent_handle: ?Handle = node.parent;
        var total_transform: Transform = node.local_transform;
        while (parent_handle) |handle| {
            const parent_node = self.pool.getPtr(handle).?;
            parent_handle = parent_node.parent;
            total_transform = parent_node.local_transform.transform_by(&total_transform);
        }

        return total_transform;
    }
};

fn removeFromList(list: *ChildList, node_handle: Handle) bool {
    for (list.constSlice(), 0..) |list_handle, i| {
        if (list_handle == node_handle) {
            _ = list.swapRemove(i);
            return true;
        }
    }

    return false;
}
