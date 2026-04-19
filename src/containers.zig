const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn SlotMap(comptime T: type) type {
    return struct {
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

        pub const empty: Self = .{};

        const Self = @This();

        list: std.ArrayList(ListEntry) = .empty,
        first_freed: ?u32 = null,

        pub fn initCapacity(gpa: Allocator, num: usize) std.mem.Allocator.Error!Self {
            return .{
                .list = try .initCapacity(gpa, num),
            };
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.list.deinit(gpa);
        }

        pub fn insert(self: *Self, gpa: Allocator, value: T) std.mem.Allocator.Error!Handle {
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
                try self.list.append(gpa, .{
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

        pub fn iterator(self: *const Self) Iterator {
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
                if (it.index < it.slice.len) {
                    var next_real_opt: ?u32 = null;
                    for (it.slice[it.index..], it.index..) |entry, i| {
                        if (entry.value != null) {
                            next_real_opt = @intCast(i);
                            break;
                        }
                    }

                    if (next_real_opt) |next_entry| {
                        it.index = next_entry + 1;

                        const list_entry = &it.slice[next_entry];
                        return .{
                            .handle = .{ .index = next_entry, .revision = list_entry.revision },
                            .value_ptr = &list_entry.value.?,
                        };
                    }
                }

                return null;
            }

            pub fn nextValue(it: *Iterator) ?*T {
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

pub fn ArrayListSet(comptime T: type, eql_fn_opt: ?*const fn (a: T, b: T) bool) type {
    return struct {
        const Self = @This();
        pub const empty: Self = .{};

        items: std.ArrayList(T) = .empty,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .items = .init(allocator) };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.items.deinit(allocator);
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!bool {
            if (self.contains(value)) return false;
            try self.items.append(allocator, value);
            return true;
        }

        pub fn remove(self: *Self, value: T) bool {
            for (self.items.items, 0..) |item, i| {
                if (eql(item, value)) {
                    _ = self.items.swapRemove(i);
                    return true;
                }
            }
            return false;
        }

        pub fn contains(self: Self, value: T) bool {
            for (self.items.items) |item| {
                if (eql(item, value)) return true;
            }
            return false;
        }

        pub fn slice(self: Self) []const T {
            return self.items.items;
        }

        pub fn count(self: Self) usize {
            return self.items.items.len;
        }

        inline fn eql(a: T, b: T) bool {
            if (comptime eql_fn_opt) |eql_fn| {
                return eql_fn(a, b);
            }
            return std.meta.eql(a, b);
        }
    };
}

pub const ComponentMap = struct {
    const type_id = @import("type_id.zig");

    pub const empty: Self = .{};

    const Self = @This();

    map: std.AutoArrayHashMapUnmanaged(type_id.TypeId, *anyopaque) = .empty,

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.map.deinit(gpa);
    }

    pub fn put(self: *Self, gpa: std.mem.Allocator, comptime T: type, value: *T) std.mem.Allocator.Error!void {
        const t_id: type_id.TypeId = type_id.typeId(T);
        try self.map.putNoClobber(gpa, t_id, value);
    }

    pub fn contains(self: Self, comptime T: type) bool {
        const t_id: type_id.TypeId = type_id.typeId(T);
        return self.map.contains(t_id);
    }

    pub fn get(self: Self, comptime T: type) ?*T {
        const t_id: type_id.TypeId = type_id.typeId(T);
        return if (self.map.get(t_id)) |ptr|
            @ptrCast(@alignCast(ptr))
        else
            null;
    }

    pub fn remove(self: Self, comptime T: type) ?*T {
        const t_id: type_id.TypeId = type_id.typeId(T);
        return if (self.map.fetchSwapRemove(t_id)) |entry|
            @ptrCast(@alignCast(entry.value))
        else
            null;
    }
};
