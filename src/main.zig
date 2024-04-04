const std = @import("std");
const log = std.log;

const c = @import("c.zig");

const StringHash = @import("string_hash.zig");
const input = @import("input.zig");
const sdl_input = @import("sdl_input.zig");
const App = @import("app.zig").App;

const InputStruct = struct {
    const Self = @This();

    some_int: usize,

    fn callback(self: *Self) input.InputContextCallback {
        return .{
            .ptr = self,
            .button_callback = trigger_button,
            .axis_callback = trigger_axis,
        };
    }

    fn trigger_button(self: *anyopaque, button: StringHash, state: input.ButtonState) void {
        _ = self;
        log.info("Button Triggered {s} -> {}", .{ button.string, state });
    }

    fn trigger_axis(self: *anyopaque, axis: StringHash, value: f32) void {
        _ = self;
        log.info("Axis Triggered {s} -> {d:.2}", .{ axis.string, value });
    }
};

pub const GameInputContext = input.InputContext{
    .name = StringHash.new("Game"),
    .buttons = &[_]StringHash{StringHash.new("Button1")},
    .axes = &[_]StringHash{StringHash.new("Axis1")},
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (general_purpose_allocator.deinit() == .leak) {
        log.err("GeneralPurposeAllocator has a memory leak!", .{});
    };

    var app = try App.init(general_purpose_allocator.allocator());
    while (app.is_running()) {
        try app.update();
    }
    app.deinit();
}
