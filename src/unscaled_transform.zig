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

pub fn get_global_transform(parent: *const Self, child: *const Self) Self {
    return .{
        .position = parent.position.add(parent.rotation.rotateVec(child.position)),
        .rotation = parent.rotation.mul(child.rotation).norm(),
    };
}

pub fn get_local_transform(parent: *const Self, other: *const Self) Self {
    const inv_rotation = parent.rotation.inverse();
    return .{
        .position = inv_rotation.rotateVec(other.position.sub(parent.position)),
        .rotation = inv_rotation.mul(other.rotation).norm(),
    };
}

pub fn eql(self: Self, other: Self) bool {
    return self.position.eql(other.position) and self.rotation.eql(other.rotation);
}

pub fn to_scaled(self: Self, scale: za.Vec3) Transform {
    return .{
        .position = self.position,
        .rotation = self.rotation,
        .scale = scale,
    };
}
