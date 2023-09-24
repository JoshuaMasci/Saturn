pub const Vec3 = struct {
    const Self = @This();

    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Self {
        return .{ .x = x, .y = y, .z = z };
    }

    const Zero = Self{ .x = 0.0, .y = 0.0, .z = 0.0 };
};

pub const Quat = struct {
    w: f32,
    x: f32,
    y: f32,
    z: f32,
};

pub const Transform = struct {
    position: Vec3,
    rotation: Quat,
    scale: Vec3,
};
