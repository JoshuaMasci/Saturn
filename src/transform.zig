const za = @import("zalgebra");

pub const Right = za.Vec3.NEG_X;
pub const Up = za.Vec3.Y;
pub const Forward = za.Vec3.Z;

const Self = @This();
position: za.Vec3 = za.Vec3.ZERO,
rotation: za.Quat = za.Quat.IDENTITY,
scale: za.Vec3 = za.Vec3.ONE,

pub const Identity: Self = .{};

pub fn getRight(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Self.Right).norm();
}

pub fn getUp(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Self.Up).norm();
}

pub fn getForward(self: Self) za.Vec3 {
    return self.rotation.rotateVec(Self.Forward).norm();
}

pub fn applyTransform(parent: *const Self, child: *const Self) Self {
    return .{
        .position = parent.position.add(parent.rotation.rotateVec(child.position.mul(parent.scale))),
        .rotation = parent.rotation.mul(child.rotation).norm(),
        .scale = parent.scale.mul(child.scale),
    };
}

pub fn getRelativeTransform(parent: *const Self, child: *const Self) Self {
    return .{
        .position = .{ .data = parent.rotation.inv().rotateVec(child.position.sub(parent.position)).data / parent.scale.data },
        .rotation = parent.rotation.inv().mul(child.rotation).norm(),
        .scale = .{ .data = child.scale.data / parent.scale.data },
    };
}
pub fn getModelMatrix(self: Self) za.Mat4 {
    return za.Mat4.recompose(self.position, self.rotation, self.scale);
}

pub fn getViewMatrix(self: Self) za.Mat4 {
    const forward = self.getForward();
    const up = self.getUp();
    return za.Mat4.RightHanded.lookAt(self.position, self.position.add(forward), up);
}
