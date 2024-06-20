const za = @import("zalgebra");
const Transform = @import("transform.zig");

const Self = @This();
position: za.Vec3 = za.Vec3.ZERO,
rotation: za.Quat = za.Quat.IDENTITY,

pub fn get_right(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Transform.Right).norm();
}

pub fn get_up(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Transform.Up).norm();
}

pub fn get_forward(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Transform.Forward).norm();
}

pub fn eql(self: Self, other: Self) bool {
    return self.position.eql(other.position) and self.rotation.eql(other.rotation);
}
