//Keep It Simple Stupid (I'm the stupid here)

const std = @import("std");

const jolt = @import("physics");
const zm = @import("zmath");

const rendering = @import("rendering/scene.zig");
const Transform = @import("transform.zig");

const GRAVITATION_CONST: f32 = 0.00000000006674;
const GRAVITATION_CONST_SMALL: f32 = GRAVITATION_CONST * 1000.0;

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
        const body_transform = self.body.getTransform();
        transform.position = zm.loadArr3(body_transform.position);
        transform.rotation = zm.normalize4(zm.loadArr4(body_transform.rotation));

        const velocity = self.body.getVelocity();
        self.linear_velocity = zm.loadArr3(velocity.linear);
        self.angular_velocity = zm.loadArr3(velocity.angular);
    }
};

pub const Entity = struct {
    const Self = @This();

    transform: Transform,
    rigid_body: RigidBodyComponent,
    collider: ?jolt.Shape = null,
    mesh: ?rendering.StaticMeshComponent = null,

    pub fn init(transform: Transform) Self {
        var rigid_body: RigidBodyComponent = .{
            .body = .init(.{
                .transform = .{
                    .position = zm.vecToArr3(transform.position),
                    .rotation = zm.vecToArr4(zm.normalize4(transform.rotation)),
                },
                .object_layer = 1,
                .motion_type = .dynamic,
                .friction = 1.0,
            }),
        };
        rigid_body.set(&transform);

        return .{
            .transform = transform,
            .rigid_body = rigid_body,
        };
    }
};

pub const World = struct {
    const Self = @This();

    physics_world: jolt.World,
    entites: std.BoundedArray(Entity, 64),

    pub fn init() Self {
        return .{
            .physics_world = .init(.{}),
            .entites = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entites.slice()) |*entity| {
            entity.rigid_body.body.deinit();
        }
        self.physics_world.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) void {
        for (self.entites.slice()) |*entity| {
            entity.rigid_body.set(&entity.transform);
        }

        self.physics_world.update(delta_time, 1);

        for (self.entites.slice()) |*entity| {
            //TODO: check behavior type
            self.updatePlanet(entity);
        }

        for (self.entites.slice()) |*entity| {
            entity.rigid_body.get(&entity.transform);
        }
    }

    pub fn buildScene(self: Self, scene: *rendering.RenderScene) void {
        for (self.entites.slice()) |entity| {
            if (entity.mesh) |mesh| {
                scene.static_meshes.append(.{ .component = mesh, .transform = entity.transform }) catch |err| std.log.err("Failed to append mesh to scene {}", .{err});
            }
        }
    }

    pub fn addSphere(self: *Self, transform: Transform, velocity: zm.Vec, radius: f32, density: f32) void {
        const MaterialAssetHandle = @import("asset/material.zig").Registry.Handle;
        const MeshAssetHandle = @import("asset/mesh.zig").Registry.Handle;

        var entity: Entity = .init(.{
            .position = transform.position,
            .rotation = transform.rotation,
            .scale = @splat(radius),
        });
        entity.rigid_body.linear_velocity = velocity;

        const sphere = jolt.Shape.initSphere(radius, density, 0);
        _ = entity.rigid_body.body.addShape(sphere, .{ 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 1.0 }, 0);
        entity.rigid_body.body.commitShapeChanges();

        entity.collider = sphere;

        self.physics_world.addBody(entity.rigid_body.body);

        entity.mesh = .{
            .mesh = MeshAssetHandle.fromRepoPath("engine:shapes/sphere.mesh").?,
            .materials = .fromSlice(&.{MaterialAssetHandle.fromRepoPath("game:materials/grid.mat").?}),
            .visable = true,
        };

        self.entites.appendAssumeCapacity(entity);
    }

    pub fn updatePlanet(self: *Self, entity: *Entity) void {
        const entity_mass = entity.collider.?.getMassProperties().mass;

        for (self.entites.slice()) |*other| {
            //TODO: need handles or something
            if (entity == other) {
                continue;
            }

            if (other.collider) |other_collider| {
                const offset = entity.transform.position - other.transform.position;

                const is_zero = zm.isNearEqual(offset, zm.splat(zm.Vec, 0.0), zm.splat(zm.Vec, 0.1));
                if (is_zero[0] and is_zero[1] and is_zero[2]) {
                    continue;
                }

                const dir = zm.normalize3(offset);
                const distance = zm.length3(offset)[0];

                const other_mass = other_collider.getMassProperties().mass;

                const force_mag: f32 = (GRAVITATION_CONST_SMALL * entity_mass * other_mass) / (distance * distance);
                if (force_mag > 0.0001) {
                    const force = zm.splat(zm.Vec, -force_mag) * dir;
                    entity.rigid_body.body.addForce(zm.vecToArr3(force), true);
                }
            }
        }
    }
};
