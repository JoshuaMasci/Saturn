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
    _ = radius; // autofix
    return 0;
}

pub fn create_box(half_extent: za.Vec3) Shape {
    _ = half_extent; // autofix
    return 0;
}

pub fn create_cylinder(
    half_height: f32,
    radius: f32,
) Shape {
    _ = half_height; // autofix
    _ = radius; // autofix
    return 0;
}

pub fn create_capsule(
    half_height: f32,
    radius: f32,
) Shape {
    _ = half_height; // autofix
    _ = radius; // autofix
    return 0;
}

pub const BodyHandle = u64;
pub const CharacterHandle = u64;
pub const Shape = u64;

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    world: saturn_physics.World,

    pub fn init(allocator: std.mem.Allocator, args: struct {
        max_bodies: u32 = 1024,
        num_body_mutexes: u32 = 0,
        max_body_pairs: u32 = 1024,
        max_contact_constraints: u32 = 1024,
    }) !Self {
        _ = args; // autofix

        return .{
            .allocator = allocator,
            .world = saturn_physics.World.init(),
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
    ) BodyHandle {
        _ = self; // autofix
        _ = tranform; // autofix
        _ = shape; // autofix
        return 0;
    }

    pub fn destory_body(self: *Self, handle: BodyHandle) void {
        _ = self; // autofix
        _ = handle; // autofix
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
