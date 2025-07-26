//Keep It Simple Stupid

const std = @import("std");

const jolt = @import("physics");
const zm = @import("zmath");

const rendering = @import("rendering/scene.zig");
const Transform = @import("transform.zig");

pub const RigidBodyComponent = struct {
    body: jolt.Body,
    linear_velocity: zm.Vec = zm.splat(zm.Vec, 0.0),
    angular_velocity: zm.Vec = zm.splat(zm.Vec, 0.0),

    pub fn set(self: *RigidBodyComponent, transform: *const Transform) void {
        self.body.setTransform(&.{
            .position = zm.vecToArr3(transform.position),
            .rotation = zm.vecToArr4(zm.normalize4(transform.rotation)),
        });
        self.body.setVelocity(&.{
            .linear = zm.vecToArr3(self.linear_velocity),
            .angular = zm.vecToArr3(self.angular_velocity),
        });
    }

    pub fn get(self: *RigidBodyComponent, transform: *Transform) void {
        const velocity = self.body.getVelocity();
        self.linear_velocity = zm.loadArr3(velocity.linear);
        self.angular_velocity = zm.loadArr3(velocity.angular);

        const body_transform = self.body.getTransform();
        transform.position = zm.loadArr3(body_transform.position);
        transform.rotation = zm.normalize4(zm.loadArr4(body_transform.rotation));
    }
};

pub const Player = struct {
    transform: Transform,
    rigid_body: RigidBodyComponent,
    collider: jolt.Shape,
    mass: f32,
};

pub const Ship = struct {
    transform: Transform,
    rigid_body: RigidBodyComponent,
    collider: jolt.Shape,
    mesh: rendering.StaticMeshComponent,
    mass: f32,
};

pub const Planet = struct {
    const Self = @This();

    transform: Transform,
    rigid_body: RigidBodyComponent,
    collider: jolt.Shape,
    mesh: rendering.StaticMeshComponent,
    mass: f32,

    pub fn init(transform: Transform, linear_velocity: zm.Vec, radius: f32, density: f32) Self {
        var rigid_body: RigidBodyComponent = .{
            .body = .init(.{}),
            .linear_velocity = linear_velocity,
        };
        rigid_body.set(&Transform);

        const collider_transform: Transform = .{};
        const collider = jolt.Shape.initSphere(radius, density, 0);
        rigid_body.body.addShape(collider, zm.vecToArr3(collider_transform.position), zm.vecToArr3(collider_transform.rotation), 0);
        rigid_body.body.commitShapeChanges();

        const mass = (4.0 / 3.0) * std.math.pi * std.math.pow(f32, radius, 3) * density;

        return .{
            .transform = transform,
            .rigid_body = rigid_body,
            .collider = collider,
            .mass = mass,
        };
    }
};

pub const World = struct {
    const Self = @This();

    physics_world: jolt.World,
    planets: std.BoundedArray(Planet, 16) = .{},

    pub fn update(self: *Self, delta_time: f32) void {
        for (self.planets.slice()) |*planet| {
            planet.rigidbody.set(&planet.transform);
        }

        self.physics_world.update(delta_time, 1);

        for (self.planets.slice()) |*planet| {
            planet.rigidbody.get(&planet.transform);
        }
    }
};
