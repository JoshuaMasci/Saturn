const zm = @import("zmath");

const Self = @This();
position: zm.Vec,
rotation: zm.Quat,
scale: zm.Vec,

pub const Identity = Self{
    .position = zm.f32x4s(0.0),
    .rotation = zm.qidentity(),
    .scale = zm.f32x4s(1.0),
};
