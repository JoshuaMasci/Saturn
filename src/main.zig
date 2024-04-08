// Library Plans
// 1. Windowing/Input/Networking/FileSys/FileDiag: SDL3 (zig wrapper or stright c?)
// 2. Other Inputs: DuelSenseLib + steam-input (Both much later down the line)
// 3. Rendering: Vulkan (zig wrapper or stright c?)
// 4. Audio: steam-audio (use c api)
// 5. Physics: Jolt (needs a c wrapper)
// 6. UI: cImgui
// 7: Mesh Loading: cgltf
// 8. Texture Loading: stb_image
// 9. Linear Math: zmath or zalgabra?

const std = @import("std");
const log = std.log;

const App = @import("app.zig").App;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (general_purpose_allocator.deinit() == .leak) {
        log.err("GeneralPurposeAllocator has a memory leak!", .{});
    };

    var app = try App.init(general_purpose_allocator.allocator());
    defer app.deinit();

    while (app.is_running()) {
        try app.update();
    }
}
