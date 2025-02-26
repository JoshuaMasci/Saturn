const input = @import("input3.zig");

pub const DebugCameraInputContext = input.InputContext(
    "DebugCamera",
    enum {
        interact,
        move_jump,
    },
    enum {
        move_left_right,
        move_up_down,
        move_forward_backward,
        rotate_yaw,
        rotate_pitch,
    },
);
