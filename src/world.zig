const std = @import("std");
const Allocator = std.mem.Allocator;

const Transform = @import("transform.zig");

pub const NodePool = ObjectPool(u16, Node);
pub const NodeHandle = NodePool.Handle;

pub const NodeComponents = struct {
    model: ?void,
    collider: ?void,
};

pub const Node = struct {
    name: ?[]const u8,
    local_transform: Transform,
    components: NodeComponents,

    parent: ?NodeHandle,
    childen: std.ArrayList(NodeHandle),
};

pub const EntityComponents = struct {
    character: ?void,
    rigid_body: ?void,
};

pub const EntityData = struct {
    name: ?[]const u8,
    transform: Transform,
    components: EntityComponents,

    root_nodes: std.ArrayList(NodeHandle),
    node_pool: NodePool,
};

pub const EntitySystems = struct {};
pub const Entity = struct {
    data: EntityData,
    systems: EntitySystems,
};

pub const WorldData = struct {};

pub const World = struct {
    data: WorldData,
    entity_pool: std.ArrayList(?Entity),
};

pub fn ObjectPool(comptime IndexType: type, comptime T: type) type {
    return struct {
        const Self = @This();

        const Entry = struct {
            revision: IndexType,
            value: ?T,
        };

        pub const Handle = struct {
            index: IndexType,
            revision: IndexType,
        };

        list: std.ArrayList(Entry),
        freed_indexes: std.ArrayList(IndexType),

        pub fn init(allocator: Allocator) Self {
            return .{
                .list = std.ArrayList(Entry).init(allocator),
                .freed_indexes = std.ArrayList(IndexType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit();
            self.freed_indexes.deinit();
        }

        pub fn insert(self: *Self, value: T) !Handle {
            var handle: Handle = undefined;
            if (self.freed_indexes.popOrNull()) |index| {
                var entry = &self.list.items[index];

                entry.value = value;
                handle = .{
                    .index = index,
                    .revision = entry.revision,
                };
            } else {
                var index: IndexType = @intCast(self.list.items.len);
                var revision: IndexType = 0;
                try self.list.append(.{
                    .revision = revision,
                    .value = value,
                });
                handle = .{ .index = index, .revision = revision };
            }
            return handle;
        }

        pub fn remove(self: *Self, handle: Handle) ?T {
            var index_usize: usize = @intCast(handle.index);
            if (self.list.items.len > index_usize) {
                var entry = &self.list.items[index_usize];

                if (entry.revision == handle.revision) {
                    if (entry.value) |value| {
                        entry.revision += 1;
                        entry.value = null;
                        return value;
                    }
                }
            }
            return null;
        }
    };
}
