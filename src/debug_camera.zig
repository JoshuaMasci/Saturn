const std = @import("std");
const zm = @import("zmath");

const input = @import("input.zig");

const Transform = @import("transform.zig");
const PerspectiveCamera = @import("camera.zig").PerspectiveCamera;

pub const DebugCamera = struct {
    const Self = @This();

    transform: Transform,
    camera: PerspectiveCamera,

    linear_speed: zm.Vec,

    linear_input: zm.Vec,

    pub const Default: Self = .{
        .transform = Transform.Identity,
        .camera = PerspectiveCamera.Default,
        .linear_speed = zm.splat(zm.Vec, 5.0),
        .linear_input = zm.splat(zm.Vec, 0.0),
    };

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        _ = self;
        std.log.info("Button {} -> {}", .{ event.button, event.state });
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        //std.log.info("Axis {} -> {:.2}", .{ event.axis, event.get_value(false) });

        switch (event.axis) {
            .debug_camera_left_right => self.linear_input[0] = event.get_value(true),
            .debug_camera_up_down => self.linear_input[1] = event.get_value(true),
            .debug_camera_forward_backward => self.linear_input[2] = event.get_value(true),
            else => {},
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        const move_amount = zm.rotate(self.transform.rotation, (self.linear_input * self.linear_speed) * zm.splat(zm.Vec, delta_time));
        self.transform.position += move_amount;
    }
};
