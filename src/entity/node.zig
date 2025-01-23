const std = @import("std");
const Transform = @import("../transform.zig");
const ObjectPool = @import("../containers.zig").HandlePool;

pub const Components = @import("game.zig").NodeComponents;

const Self = @This();

pub const Pool = ObjectPool(Self);
pub const Handle = Pool.Handle;

handle: Handle,

local_transform: Transform = .{},
components: Components = .{},

parent: ?Handle = null,
childen: ChildList = ChildList{},

pub const ChildList = std.BoundedArray(Handle, 16);

pub const Nodes = struct {
    root_nodes: ChildList,
    pool: Pool,

    pub fn init(allocator: std.mem.Allocator) Nodes {
        return .{
            .root_nodes = ChildList{},
            .pool = Pool.init(allocator),
        };
    }

    pub fn deinit(self: *Nodes) void {
        self.pool.deinit();
    }

    pub fn addNode(
        self: *Nodes,
        parent: ?Handle,
        local_transform: Transform,
        components: Components,
    ) !Handle {
        const handle = try self.pool.insert(.{
            .parent = parent,
            .handle = undefined,
            .local_transform = local_transform,
            .components = components,
        });
        self.pool.getPtr(handle).?.handle = handle;

        if (parent) |parent_handle| {
            if (self.pool.getPtr(parent_handle)) |parent_node| {
                parent_node.childen.append(handle) catch return error.child_node_list_full;
            } else {
                return error.invalid_parent_node;
            }
        } else {
            self.root_nodes.append(handle) catch return error.root_node_list_full;
        }

        return handle;
    }

    pub fn removeNode(self: *Nodes, node_handle: Handle) !void {
        if (self.pool.remove(node_handle)) |node| {
            for (node.childen.slice()) |child_handle| {
                try self.remove_node(child_handle);
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
