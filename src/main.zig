// Library Plans
// 1. Windowing/Input/Networking/FileSys/FileDiag: SDL3 (zig wrapper or stright c?)
// 2. Other Inputs: DuelSenseLib + steam-input (Both much later down the line)
// 3. Rendering: Vulkan (zig wrapper or stright c?) / Opengl (using glad)
// 4. Audio: steam-audio (use c api)
// 5. Physics: Jolt (needs a c wrapper)
// 6. UI: cImgui
// 7: Mesh Loading: cgltf
// 8. Texture Loading: stb_image
// 9. Linear Math: zmath or zalgabra?

const std = @import("std");
const log = std.log;

const App = @import("app.zig").App;

const TEREBYTE = std.math.pow(usize, 1000, 4);
const GIGABYTE = std.math.pow(usize, 1000, 3);
const MEGABYTE = std.math.pow(usize, 1000, 2);
const KILOBYTE = std.math.pow(usize, 1000, 1);

fn human_readable_bytes(value: usize) usize {
    if (value > TEREBYTE) {
        return value / TEREBYTE;
    } else if (value > GIGABYTE) {
        return value / GIGABYTE;
    } else if (value > MEGABYTE) {
        return value / MEGABYTE;
    } else if (value > KILOBYTE) {
        return value / KILOBYTE;
    } else {
        return value;
    }
}

fn human_readable_unit(value: usize) []const u8 {
    if (value > TEREBYTE) {
        return "TB";
    } else if (value > GIGABYTE) {
        return "GB";
    } else if (value > MEGABYTE) {
        return "MB";
    } else if (value > KILOBYTE) {
        return "KB";
    } else {
        return "B";
    }
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
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

        const memory_usage = human_readable_bytes(general_purpose_allocator.total_requested_bytes);
        const memory_usage_unit = human_readable_unit(general_purpose_allocator.total_requested_bytes);

        try app.update(delta_time_s, .{ .value = memory_usage, .unit_str = memory_usage_unit });
    }
}
