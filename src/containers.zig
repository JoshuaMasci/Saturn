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

        list: std.ArrayList(ListEntry),
        first_freed: ?u32,

        pub fn init(allocator: Allocator) Self {
            return .{
                .list = std.ArrayList(ListEntry).init(allocator),
                .first_freed = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit();
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
                try self.list.append(.{
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

pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();

        const List = std.DoublyLinkedList(T);

        arena: std.heap.ArenaAllocator,
        free: List = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn new(self: *Self) !*T {
            const obj = if (self.free.popFirst()) |item|
                item
            else
                try self.arena.allocator().create(List.Node);
            return &obj.data;
        }

        pub fn delete(self: *Self, obj: *T) void {
            const node: *List.Node = @fieldParentPtr("data", obj);
            self.free.append(node);
        }
    };
}

pub fn HandlePtrPool(comptime Handle: type, comptime T: type) type {
    return struct {
        const Self = @This();

        mutex: std.Thread.Mutex,
        pool: ObjectPool(T),
        map: std.AutoArrayHashMap(Handle, *T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .pool = ObjectPool(T).init(allocator),
                .map = std.AutoArrayHashMap(Handle, *T).init(allocator),
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();

            if (comptime std.meta.hasFn(T, "deinit")) {
                for (self.map.values()) |value| {
                    value.deinit();
                }
            }

            self.pool.deinit();
            self.map.deinit();
        }

        pub fn create(self: *Self, handle: Handle) *T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Check if the object is already created
            if (self.map.contains(handle)) {
                std.debug.panic("Handle({}) already exists in map", .{handle});
            }

            // Create a new object from the pool
            const obj = self.pool.new() catch |err| std.debug.panic("Failed to alloc from pool: {}", .{err});
            self.map.put(handle, obj) catch |err| std.debug.panic("Failed to insert into map: {}", .{err});
            return obj;
        }

        pub fn destroy(self: *Self, handle: Handle) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Remove the object from the map
            if (self.map.contains(handle)) {
                const value = self.map.get(handle) orelse return;

                if (comptime std.meta.hasFn(T, "deinit")) {
                    value.deinit();
                }

                self.pool.delete(value);
                self.map.remove(handle);
            }
        }

        pub fn get(self: *Self, handle: Handle) ?*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.map.get(handle);
        }

        pub fn getValues(self: *Self, allocator: std.mem.Allocator) []*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            const src_values = self.map.values();
            const values = allocator.alloc(*T, src_values.len) catch |err| std.debug.panic("Failed to alloc from temp list: {}", .{err});
            @memcpy(values, src_values);
            return values;
        }
    };
}

pub fn LockQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const LockedList = struct {
            mutex: *std.Thread.Mutex,
            list: []T,

            pub fn deinit(self: @This()) void {
                self.mutex.unlock();
            }
        };

        mutex: std.Thread.Mutex,
        list: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .mutex = .{},
                .list = std.ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            self.list.deinit();
        }

        pub fn push(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.list.append(value);
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.list.popOrNull();
        }

        pub fn popAll(self: *Self) ?LockedList {
            self.mutex.lock();

            if (self.list.items.len == 0) {
                self.mutex.unlock();
                return null;
            }

            return .{
                .mutex = &self.mutex,
                .list = self.list.items,
            };
        }
    };
}
