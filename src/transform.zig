const linear_math = @import("linear_math.zig");

pub const Transform = struct {
    const Self = @This();

    position: linear_math.Vector3,
    orientation: linear_math.Quaternion,
    scale: linear_math.Vector3,

    pub const identity = Self{
        .position = linear_math.Vector3.zero,
        .orientation = linear_math.Quaternion.identity,
        .scale = linear_math.Vector3.one,
    };
};
