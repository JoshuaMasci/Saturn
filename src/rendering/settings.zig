pub const WindowSize = union(enum) {
    windowed: [2]i32,
    fullscreen,
    maximized,
};

pub const VerticalSync = enum {
    on,
    half,
    variable,
    off,
};

pub const RenderSettings = struct {
    window_name: [:0]const u8,
    size: WindowSize,
    vsync: VerticalSync,
};
