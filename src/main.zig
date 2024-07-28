// Library Plans
// 1. Windowing/Input/Networking/FileSys/FileDiag: SDL3 zig
// 2. Other Inputs: DuelSenseLib + steam-input (Both much later down the line)
// 3. Rendering: Vulkan (zig wrapper) / Opengl (using zopengl)
// 4. Audio: steam-audio (use c api)
// 5. Physics: zjolt
// 6. UI: zimgui
// 7: Mesh Loading: zmesh
// 8. Texture Loading: stb_image
// 9. Linear Math: zalgabra

const std = @import("std");
const log = std.log;

const App = @import("app.zig").App;

pub fn main() !void {
    const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true });
    var general_purpose_allocator = GeneralPurposeAllocator{};
    defer if (general_purpose_allocator.deinit() == .leak) {
        log.err("GeneralPurposeAllocator has a memory leak!", .{});
    };
    const allocator = general_purpose_allocator.allocator();

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
