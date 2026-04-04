const std = @import("std");

const zm = @import("zmath");

const Camera = @import("rendering/camera.zig").Camera;
const Transform = @import("transform.zig");

const Self = @This();

camera: Camera = .Default,
transform: Transform = .{},

linear_speed: zm.Vec = zm.splat(zm.Vec, 5.0),
angular_speed: zm.Vec = zm.splat(zm.Vec, std.math.pi),
