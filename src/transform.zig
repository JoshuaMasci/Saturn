const za = @import("zalgebra");
const UnscaledTransform = @import("unscaled_transform.zig");

pub const Right = za.Vec3.NEG_X;
pub const Up = za.Vec3.Y;
pub const Forward = za.Vec3.Z;

const Self = @This();
position: za.Vec3 = za.Vec3.ZERO,
rotation: za.Quat = za.Quat.IDENTITY,
scale: za.Vec3 = za.Vec3.ONE,

pub const Identity: Self = .{};

pub fn get_right(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Self.Right).norm();
}

pub fn get_up(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Self.Up).norm();
}

pub fn get_forward(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Self.Forward).norm();
}

pub fn get_unscaled(self: Self) UnscaledTransform {
    return .{
        .position = self.position,
        .rotation = self.rotation,
    };
}

pub fn apply_unscaled(self: *Self, transform: *const UnscaledTransform) void {
    self.position = transform.position;
    self.rotation = transform.rotation;
}

pub fn get_model_matrix(self: Self) za.Mat4 {
    const translation = za.Mat4.fromTranslate(self.position);
    const rotation = self.rotation.toMat4();
    const scale = za.Mat4.fromScale(self.scale);
    return scale.mul(translation).mul(rotation);
}

pub fn get_view_matrix(self: Self) za.Mat4 {
    const forward = self.get_forward();
    const up = self.get_up();
    return za.Mat4.RightHanded.lookAt(self.position, self.position.add(forward), up);
}
