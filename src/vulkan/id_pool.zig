const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;

pub const IdPool = struct {
    const Self = @This();

    next_id: u32 = 0,
    freed_ids: std.ArrayList(u32),

    pub fn init(allocator: *Allocator, start_id: u32) Self {
        return Self{
            .next_id = start_id,
            .freed_ids = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.freed_ids.deinit();
    }

    pub fn get(self: *Self) u32 {
        var new_index: u32 = undefined;
        if (self.freed_ids.items.len > 0) {
            new_index = self.freed_ids.pop();
        } else {
            new_index = self.next_id;
            self.next_id += 1;
        }

        return new_index;
    }

    pub fn free(self: *Self, id: u32) void {
        self.freed_ids.append(id) catch {
            panic("Failed to append freed id", .{});
        };
    }
};
