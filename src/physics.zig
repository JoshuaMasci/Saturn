const std = @import("std");
const za = @import("zalgebra");

const saturn_physics = @import("saturn_physics");

const UnscaledTransform = @import("unscaled_transform.zig");
const ObjectPool = @import("object_pool.zig").ObjectPool;

pub fn init(allocator: std.mem.Allocator) !void {
    saturn_physics.init(allocator);
}

pub fn deinit() void {
    saturn_physics.deinit();
}

pub fn create_sphere(radius: f32) Shape {
    return saturn_physics.Shape.init_sphere(radius, 1.0);
}

pub fn create_box(half_extent: za.Vec3) Shape {
    return saturn_physics.Shape.init_box(half_extent.toArray(), 1.0);
}

pub fn create_cylinder(
    half_height: f32,
    radius: f32,
) Shape {
    _ = half_height; // autofix
    _ = radius; // autofix
    return .{ .handle = 0 };
}

pub fn create_capsule(
    half_height: f32,
    radius: f32,
) Shape {
    _ = half_height; // autofix
    _ = radius; // autofix
    return .{ .handle = 0 };
}

pub const BodyHandle = saturn_physics.BodyHandle;
pub const CharacterHandle = u64;
pub const Shape = saturn_physics.Shape;

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    world: saturn_physics.World,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .world = saturn_physics.World.init(.{
                .max_bodies = 1024,
                .num_body_mutexes = 0,
                .max_body_pairs = 1024,
                .max_contact_constraints = 1024,
                .temp_allocation_size = 10 * 1024 * 1024,
            }),
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        self.world.update(delta_time, 1);
    }

    pub fn create_body(
        self: *Self,
        tranform: UnscaledTransform,
        shape: Shape,
        dynamic: bool,
    ) BodyHandle {
        return self.world.add_body(&.{
            .shape = shape,
            .postion = tranform.position.toArray(),
            .rotation = tranform.rotation.toArray(),
            .motion_type = if (dynamic) .Dynamic else .Static,
            .gravity_factor = 1.0,
        });
    }

    pub fn destory_body(self: *Self, handle: BodyHandle) void {
        self.world.remove_body(handle);
    }

    pub fn get_body_transform(self: *Self, handle: BodyHandle) UnscaledTransform {
        const transform = self.world.get_body_transform(handle);
        return .{
            .position = za.Vec3.fromArray(transform.position),
            .rotation = za.Quat.fromArray(transform.rotation),
        };
    }

    pub fn create_character(
        self: *Self,
        transform: UnscaledTransform,
        shape: Shape,
    ) CharacterHandle {
        _ = self; // autofix
        _ = transform; // autofix
        _ = shape; // autofix
        return 0;
    }
    pub fn destroy_character(self: *Self, handle: CharacterHandle) void {
        _ = self; // autofix
        _ = handle; // autofix
    }
};
