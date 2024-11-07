const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn StableObjectPool(comptime T: type) type {
    const ObjectIndex = u16;
    const RevisionIndex = u16;

    return struct {
        const Self = @This();

        const ListEntry = struct {
            revision: ObjectIndex,
            value: ?T,
            next_freed: ?RevisionIndex,
        };

        pub const Handle = struct {
            index: ObjectIndex,
            revision: RevisionIndex,
        };

        const SegmentedList = std.SegmentedList(ListEntry, 512);

        allocator: std.mem.Allocator,
        list: *SegmentedList,
        first_freed: ?ObjectIndex,

        pub fn init(allocator: Allocator) !Self {
            const list_ptr = try allocator.create(SegmentedList);
            list_ptr.* = .{};
            return .{
                .allocator = allocator,
                .list = list_ptr,
                .first_freed = null,
            };
        }

        pub fn deinit(self: *Self) void {
            if (comptime std.meta.hasFn(T, "deinit")) {
                var iter = self.list.iterator(0);
                while (iter.next()) |entry| {
                    if (entry.value) |*value| {
                        value.deinit();
                    }
                }
            }
            self.list.deinit(self.allocator);
            self.allocator.destroy(self.list);
        }

        pub fn insert(self: *Self, value: T) !Handle {
            var handle: Handle = undefined;
            if (self.first_freed) |index| {
                var entry = self.list.at(index);

                entry.value = value;
                handle = .{
                    .index = index,
                    .revision = entry.revision,
                };
                self.first_freed = entry.next_freed;
                entry.next_freed = null;
            } else {
                const index: ObjectIndex = @intCast(self.list.len);
                const revision: RevisionIndex = 1;
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

        fn append_freed_list(self: *Self, index: ObjectIndex) void {
            if (self.first_freed) |freed_index| {
                var current_index = freed_index;
                while (self.list.at(@intCast(current_index)).next_freed) |next_freed| {
                    current_index = next_freed;
                }
                self.list.at(@intCast(current_index)).next_freed = index;
            } else {
                self.first_freed = index;
            }
        }

        pub fn get(self: Self, handle: Handle) ?*T {
            if (self.list.len > handle.index) {
                var entry = self.list.at(@intCast(handle.index));
                if (entry.revision == handle.revision) {
                    if (entry.value) |*value| {
                        return value;
                    }
                }
            }
            return null;
        }

        pub fn iterator(self: Self) Iterator {
            return .{ .list_iter = self.list.iterator(0) };
        }
        pub const Iterator = struct {
            list_iter: SegmentedList.Iterator,

            pub fn next(it: *Iterator) ?*T {
                while (it.list_iter.next()) |entry| {
                    if (entry.value != null) {
                        return &entry.value.?;
                    }
                }

                return null;
            }
        };
    };
}
