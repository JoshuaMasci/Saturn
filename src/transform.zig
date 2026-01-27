const zm = @import("zmath");

pub const Right = zm.f32x4(1, 0, 0, 0);
pub const Up = zm.f32x4(0, 1, 0, 0);
pub const Forward = zm.f32x4(0, 0, 1, 0);

const Self = @This();
position: zm.Vec = zm.splat(zm.Vec, 0.0),
rotation: zm.Quat = zm.qidentity(),
scale: zm.Vec = zm.splat(zm.Vec, 1.0),

pub const Identity: Self = .{};

pub fn getRight(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Right));
}

pub fn getUp(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Up));
}

pub fn getForward(self: Self) zm.Vec {
    return zm.normalize3(zm.rotate(self.rotation, Forward));
}

pub fn applyTransform(parent: *const Self, child: *const Self) Self {
    const rotated_scaled_pos = zm.rotate(parent.rotation, child.position) * parent.scale;
    return .{
        .position = parent.position + rotated_scaled_pos,
        .rotation = zm.normalize4(zm.qmul(parent.rotation, child.rotation)),
        .scale = parent.scale * child.scale,
    };
}

pub fn getRelativeTransform(parent: *const Self, child: *const Self) Self {
    const inv_rotation = zm.inverse(parent.rotation);
    const pos_diff = child.position - parent.position;
    const relative_pos = zm.rotate(inv_rotation, pos_diff) / parent.scale;

    return .{
        .position = relative_pos,
        .rotation = zm.normalize4(zm.qmul(inv_rotation, child.rotation)),
        .scale = child.scale / parent.scale,
    };
}

pub fn transformPoint(self: *const Self, point: zm.Vec) zm.Vec {
    return (zm.rotate(self.rotation, point) * self.scale) + self.position;
}

pub fn getModelMatrix(self: Self) zm.Mat {
    const translation_matrix = zm.translationV(self.position);
    const rotation_matrix = zm.matFromQuat(self.rotation);
    const scale_matrix = zm.scalingV(self.scale);
    return zm.mul(scale_matrix, zm.mul(rotation_matrix, translation_matrix));
}

pub fn getNormalMatrix(self: Self) zm.Mat {
    const rotation_matrix = zm.matFromQuat(self.rotation);
    const scale_matrix = zm.scalingV(self.scale);
    const rotation_scale = zm.mul(scale_matrix, rotation_matrix);

    //Transposing the inverse handles issues with non-uniform scaling
    return zm.transpose(zm.inverse(rotation_scale));
}

pub fn getViewMatrix(self: Self) zm.Mat {
    const forward = self.getForward();
    const up = self.getUp();
    return zm.lookAtRh(self.position, self.position + forward, up);
}
