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

    var frame_count: usize = 0;
    const MemReportFrequency = 500;

    var app = try App.init(allocator);
    defer app.deinit();

    while (app.is_running()) {
        if (frame_count % MemReportFrequency == 0) {
            log.info("GeneralPurposeAllocator Memory Usage: {} {s}", .{ human_readable_bytes(general_purpose_allocator.total_requested_bytes), human_readable_unit(general_purpose_allocator.total_requested_bytes) });
        }
        try app.update();
        frame_count += 1;
    }
}
