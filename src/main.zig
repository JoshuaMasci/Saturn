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

    var app = try App.init(allocator);
    defer app.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len > 1) {
        const file_path = args[1];
        std.log.info("Loading File: {s}", .{file_path});
        const Mesh = @import("mesh.zig");

        if (Mesh.load_gltf_mesh(allocator, file_path, &app.game_renderer)) |mesh| {
            app.loaded_mesh = mesh;
        } else |err| {
            log.err("Loading {s} failed with {}", .{ file_path, err });
        }
    }

    var last_frame_time_ns = std.time.nanoTimestamp();
    var frames_since_last: usize = 0;

    while (app.is_running()) {
        const LOG_FREQENCY_SECONDS = 1;

        const current_time_ns = std.time.nanoTimestamp();
        const time_since_last_frame_ns = current_time_ns - last_frame_time_ns;
        if (time_since_last_frame_ns > (std.time.ns_per_s * LOG_FREQENCY_SECONDS)) {
            const time_since_last_frame_ms = @as(f32, @floatFromInt(time_since_last_frame_ns)) / std.time.ns_per_ms;
            const average_frame_time = time_since_last_frame_ms / @as(f32, @floatFromInt(frames_since_last));

            const memory_usage = human_readable_bytes(general_purpose_allocator.total_requested_bytes);
            const memory_usage_unit = human_readable_unit(general_purpose_allocator.total_requested_bytes);

            log.info("Perf\n\tFPS: {}\n\tFrame Time: {d:.3}ms\n\tMemory Usage: {} {s}", .{
                frames_since_last,
                average_frame_time,
                memory_usage,
                memory_usage_unit,
            });

            last_frame_time_ns = current_time_ns;
            frames_since_last = 0;
        }

        try app.update();
        frames_since_last += 1;
    }
}
