usingnamespace @import("linear_math/vector2.zig");
usingnamespace @import("linear_math/vector3.zig");
usingnamespace @import("linear_math/vector4.zig");
usingnamespace @import("linear_math/matrix4.zig");
usingnamespace @import("linear_math/quaternion.zig");

pub const Vector2 = Vector2Fn(f32);
pub const Vector3 = Vector3Fn(f32);
pub const Vector4 = Vector4Fn(f32);
pub const Quaternion = QuaternionFn(f32);
pub const Matrix4 = Matrix4Fn(f32);
