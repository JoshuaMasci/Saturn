const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn ObjectPool(comptime IndexType: type, comptime T: type) type {
    switch (@typeInfo(IndexType)) {
        .Int => |info| {
            if (info.signedness == .signed) {
                @compileError("Invalid type for index: " ++ @typeName(IndexType) ++ ". Only unsigned ints may be used for index types");
            }
        },
        else => {
            @compileError("Invalid type for index: " ++ @typeName(IndexType) ++ ". Only unsigned ints may be used for index types");
        },
    }

    return struct {
        const Self = @This();

        const ListEntry = struct {
            revision: IndexType,
            value: ?T,
        };

        pub const Handle = struct {
            index: IndexType,
            revision: IndexType,
        };

        list: std.ArrayList(ListEntry),
        freed_indexes: std.ArrayList(IndexType),

        pub fn init(allocator: Allocator) Self {
            return .{
                .list = std.ArrayList(ListEntry).init(allocator),
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
                const index: IndexType = @intCast(self.list.items.len);
                const revision: IndexType = 0;
                try self.list.append(.{
                    .revision = revision,
                    .value = value,
                });
                handle = .{ .index = index, .revision = revision };
            }
            return handle;
        }

        pub fn remove(self: *Self, handle: Handle) !?T {
            if (self.list.items.len > handle.index) {
                var entry = &self.list.items[handle.index];

                if (entry.revision == handle.revision) {
                    if (entry.value) |value| {
                        entry.revision += 1;
                        entry.value = null;
                        try self.freed_indexes.append(handle.index);
                        return value;
                    }
                }
            }
            return null;
        }

        pub fn get(self: Self, handle: Handle) ?T {
            if (self.list.items.len > handle.index) {
                const entry = &self.list.items[handle.index];
                if (entry.revision == handle.revision) {
                    if (entry.value) |value| {
                        return value;
                    }
                }
            }
            return null;
        }

        pub fn getPtr(self: Self, handle: Handle) ?*T {
            if (self.list.items.len > handle.index) {
                var entry = &self.list.items[handle.index];
                if (entry.revision == handle.revision) {
                    if (entry.value) |*value| {
                        return value;
                    }
                }
            }
            return null;
        }

        pub fn iterator(self: Self) Iterator {
            return .{
                .slice = self.list.items,
                .index = 0,
            };
        }
        const Entry = struct {
            handle: Handle,
            value_ptr: *T,
        };
        pub const Iterator = struct {
            slice: []ListEntry,
            index: IndexType,

            pub fn next(it: *Iterator) ?Entry {
                if (it.index >= it.slice.len) return null;

                const list_entry = &it.slice[it.index];
                const result = .{
                    .handle = .{ .index = it.index, .revision = list_entry.revision },
                    .value_ptr = &list_entry.value.?,
                };

                var next_index = it.index + 1;
                while (next_index < it.slice.len) {
                    if (it.slice[next_index].value) |_| {
                        break;
                    } else {
                        next_index += 1;
                    }
                }

                it.index = next_index;
                return result;
            }

            /// Reset the iterator to the initial index
            pub fn reset(it: *Iterator) void {
                it.index = 0;
            }
        };
    };
}
