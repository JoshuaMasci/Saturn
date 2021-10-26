usingnamespace @import("linear_math.zig");

pub const Transform = struct {
    const Self = @This();

    position: linear_math.Vector3,
    orientation: linear_math.Quaternion,
    scale: linear_math.Vector3,

    pub const identity = Self{
        .position = Vector3.zero,
        .orientation = Quaternion.identity,
        .scale = Vector3.one,
    };
};
