const std = @import("std");

const App = @import("app.zig").App;

const global = @import("global.zig");

pub fn main() !void {
    const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true });
    var general_purpose_allocator = GeneralPurposeAllocator{};
    defer if (general_purpose_allocator.deinit() == .leak) {
        std.log.err("GeneralPurposeAllocator has a memory leak!", .{});
    };
    const allocator = general_purpose_allocator.allocator();

    try global.init(allocator);
    defer global.deinit();

    const zstbi = @import("zstbi");
    zstbi.init(allocator);
    defer zstbi.deinit();

    var app = try App.init(allocator);
    defer app.deinit();

    var last_frame_time_ns = std.time.nanoTimestamp();

    while (app.is_running()) {
        const current_time_ns = std.time.nanoTimestamp();
        const delta_time_ns = current_time_ns - last_frame_time_ns;
        const delta_time_s = @as(f32, @floatFromInt(delta_time_ns)) / std.time.ns_per_s;
        last_frame_time_ns = current_time_ns;

        try app.update(delta_time_s, general_purpose_allocator.total_requested_bytes);
    }
}
