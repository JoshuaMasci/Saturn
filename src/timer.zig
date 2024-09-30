const Self = @This();
const std = @import("std");

start_time: ?std.time.Instant,

pub fn start() Self {
    return .{ .start_time = std.time.Instant.now() catch null };
}

pub fn end(self: Self, scope_name: []const u8) void {
    if (self.start_time) |start_time| {
        const end_time = std.time.Instant.now() catch return;
        const time_ns: f32 = @floatFromInt(end_time.since(start_time));
        std.log.info("Scope \"{s}\" took: {d:.3} ms", .{ scope_name, time_ns / std.time.ns_per_ms });
    }
}
