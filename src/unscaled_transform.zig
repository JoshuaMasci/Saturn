const zm = @import("zmath");
const Transform = @import("transform.zig");

const Self = @This();
position: zm.Vec = zm.f32x4s(0.0),
rotation: zm.Quat = zm.qidentity(),

pub fn get_right(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Transform.Right));
}

pub fn get_forward(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Transform.Forward));
}

pub fn get_up(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Transform.Up));
}
