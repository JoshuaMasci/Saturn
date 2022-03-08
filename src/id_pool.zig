const std = @import("std");

const Self = @This();

max_id: u32,
next_id: u32,
freed_ids: std.ArrayList(u32),

pub fn init(allocator: std.mem.Allocator, starting_id: u32, max_id: u32) Self {
    return .{
        .max_id = max_id,
        .next_id = starting_id,
        .freed_ids = std.ArrayList(u32).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.freed_ids.deinit();
}

pub fn get(self: *Self) u32 {
    if (self.freed_ids.popOrNull()) |id| {
        return id;
    } else {
        var id = self.next_id;
        self.next_id += 1;
        if (id > self.max_id) {
            std.debug.panic("Id pool out of range! new_id: {} max_id: {}", .{ id, self.max_id });
        }
        return id;
    }
}

pub fn free(self: *Self, id: u32) void {
    self.freed_ids.append(id) catch {
        std.debug.panic("Failed to append freed id to list", .{});
    };
}
