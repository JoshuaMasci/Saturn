const std = @import("std");
const za = @import("zalgebra");

const Transform = @import("transform.zig");

const physics_system = @import("physics.zig");
const rendering_system = @import("rendering.zig");

const Self = @This();

transform: Transform,
body: ?physics_system.BodyHandle,
instance: ?rendering_system.SceneInstanceHandle,

linear_force: za.Vec2 = za.Vec2.set(5.0),
linear_input: za.Vec2 = za.Vec2.ZERO,
