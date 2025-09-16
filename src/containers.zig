const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn HandlePool(comptime T: type) type {
    return struct {
        const Self = @This();

        const ListEntry = struct {
            revision: u32,
            next_freed: ?u32,
            value: ?T,
        };

        pub const Handle = struct {
            index: u32,
            revision: u32,

            pub fn toU64(self: @This()) u64 {
                const index = @as(u64, @intCast(self.index)) << 32;
                const revision: u64 = @intCast(self.revision);
                return index | revision;
            }

            pub fn fromU64(value: u64) @This() {
                return .{
                    .index = @intCast(value >> 32),
                    .revision = @intCast(value & 0xFFFFFFFF),
                };
            }
        };

        allocator: Allocator,
        list: std.ArrayList(ListEntry),
        first_freed: ?u32,

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .list = .empty,
                .first_freed = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit(self.allocator);
        }

        pub fn deinit_with_entries(self: *Self) void {
            if (comptime std.meta.hasFn(T, "deinit")) {
                for (self.list.items) |*entry| {
                    if (entry.value) |*value| {
                        value.deinit();
                    }
                }
            }
            self.deinit();
        }

        pub fn insert(self: *Self, value: T) !Handle {
            var handle: Handle = undefined;
            if (self.first_freed) |index| {
                var entry = &self.list.items[index];

                entry.value = value;
                handle = .{
                    .index = index,
                    .revision = entry.revision,
                };
                self.first_freed = entry.next_freed;
                entry.next_freed = null;
            } else {
                const index: u32 = @intCast(self.list.items.len);
                const revision: u32 = 0;
                try self.list.append(self.allocator, .{
                    .revision = revision,
                    .value = value,
                    .next_freed = null,
                });
                handle = .{ .index = index, .revision = revision };
            }
            return handle;
        }

        pub fn remove(self: *Self, handle: Handle) ?T {
            if (self.list.items.len > handle.index) {
                var entry = &self.list.items[handle.index];

                if (entry.revision == handle.revision) {
                    if (entry.value) |value| {
                        entry.revision += 1;
                        entry.value = null;
                        entry.next_freed = null;
                        self.append_freed_list(handle.index);
                        return value;
                    }
                }
            }
            return null;
        }

        fn append_freed_list(self: *Self, index: u32) void {
            if (self.first_freed) |freed_index| {
                var current_index = freed_index;
                while (self.list.items[current_index].next_freed) |next_freed| {
                    current_index = next_freed;
                }
                self.list.items[current_index].next_freed = index;
            } else {
                self.first_freed = index;
            }
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
            index: u32,

            pub fn next(it: *Iterator) ?Entry {
                if (it.index >= it.slice.len) return null;

                const list_entry = &it.slice[it.index];
                if (list_entry.value == null) {
                    return null;
                }

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

            pub fn next_value(it: *Iterator) ?*T {
                if (it.next()) |entry| {
                    return entry.value_ptr;
                } else {
                    return null;
                }
            }

            /// Reset the iterator to the initial index
            pub fn reset(it: *Iterator) void {
                it.index = 0;
            }
        };
    };
}
