const zm = @import("zmath");

pub const Right = zm.f32x4(1.0, 0.0, 0.0, 0.0);
pub const Up = zm.f32x4(0.0, 1.0, 0.0, 0.0);
pub const Forward = zm.f32x4(0.0, 0.0, 1.0, 0.0);

const Self = @This();
position: zm.Vec,
rotation: zm.Quat,
scale: zm.Vec,

pub const Identity = Self{
    .position = zm.f32x4s(0.0),
    .rotation = zm.qidentity(),
    .scale = zm.f32x4s(1.0),
};

pub fn get_model_matrix(self: Self) zm.Mat {
    const translation = zm.translationV(self.position);
    const rotation = zm.quatToMat(self.rotation);
    const scale = zm.scalingV(self.scale);
    return zm.mul(zm.mul(translation, rotation), scale);
}

pub fn get_view_matrix(self: Self) zm.Mat {
    const forward = self.get_forward();
    const up = self.get_up();
    return zm.lookToRh(self.position, forward, up);
}

pub fn get_right(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Right));
}

pub fn get_forward(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Forward));
}

pub fn get_up(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Up));
}
