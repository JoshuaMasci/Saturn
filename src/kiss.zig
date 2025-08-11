//Keep It Simple Stupid (I'm the stupid here)

const std = @import("std");

const jolt = @import("physics");
const zm = @import("zmath");

const rendering = @import("rendering/scene.zig");
const Transform = @import("transform.zig");

const PlatformInput = @import("platform/sdl3.zig").Input;
const Controller = @import("platform/sdl3/controller.zig");

const GRAVITATION_CONST: f32 = 0.00000000006674;

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

pub const EntityBehavior = enum {
    none,
    planet,
    ship,
};

pub const Entity = struct {
    const Self = @This();

    behavior: EntityBehavior = .none,
    transform: Transform,
    rigid_body: RigidBodyComponent,
    collider: ?jolt.Shape = null,
    mesh: ?rendering.StaticMeshComponent = null,

    pub fn init(transform: Transform, motion_type: jolt.MotionType) Self {
        const rigid_body: RigidBodyComponent = .{
            .body = .init(.{
                .transform = .{
                    .position = zm.vecToArr3(transform.position),
                    .rotation = zm.vecToArr4(zm.normalize4(transform.rotation)),
                },
                .object_layer = 1,
                .motion_type = motion_type,
                .friction = 1.0,
            }),
        };

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

    pub fn update(self: *Self, delta_time: f32, input: *PlatformInput) void {
        for (self.entites.slice()) |*entity| {
            entity.rigid_body.set(&entity.transform);
        }

        self.physics_world.update(delta_time, 1);

        for (self.entites.slice()) |*entity| {
            switch (entity.behavior) {
                .none => {},
                .planet => self.updatePlanet(entity),
                .ship => self.updateShip(entity, input),
            }
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

    pub fn addPlanet(self: *Self, transform: Transform, velocity: zm.Vec, motion_type: jolt.MotionType, radius: f32, density: f32) void {
        const MaterialAssetHandle = @import("asset/material.zig").Registry.Handle;
        const MeshAssetHandle = @import("asset/mesh.zig").Registry.Handle;

        var entity: Entity = .init(
            .{
                .position = transform.position,
                .rotation = transform.rotation,
                .scale = @splat(radius),
            },
            motion_type,
        );
        entity.behavior = .planet;
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

    pub fn addShip(self: *Self, allocator: std.mem.Allocator, transform: Transform, velocity: zm.Vec) !void {
        const MaterialAssetHandle = @import("asset/material.zig").Registry.Handle;
        const MeshAssetHandle = @import("asset/mesh.zig").Registry.Handle;
        const global = @import("global.zig");

        var entity: Entity = .init(
            .{
                .position = transform.position,
                .rotation = transform.rotation,
            },
            .dynamic,
        );
        entity.behavior = .ship;
        entity.rigid_body.linear_velocity = velocity;

        const ship_mesh_asset = MeshAssetHandle.fromRepoPath("game:models/CubeLander.mesh").?;

        const physics_shape: jolt.Shape = shp: {
            var mesh = try global.assets.meshes.loadAsset(allocator, ship_mesh_asset);
            defer mesh.deinit(allocator);

            var cube_shape = jolt.Shape.initBox(.{ 3, 3, 6 }, 100.0, 0);
            defer cube_shape.deinit();

            var physics_mesh: @import("world_gen.zig").PhysicsMesh = try .fromMesh(allocator, mesh);
            defer physics_mesh.deinit(allocator);

            break :shp jolt.Shape.initMeshWithMass(physics_mesh.positions, physics_mesh.indices, cube_shape.getMassProperties(), 0);
        };

        _ = entity.rigid_body.body.addShape(physics_shape, .{ 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 1.0 }, 0);
        entity.rigid_body.body.commitShapeChanges();

        entity.collider = physics_shape;

        self.physics_world.addBody(entity.rigid_body.body);

        entity.mesh = .{
            .mesh = ship_mesh_asset,
            .materials = .fromSlice(&.{MaterialAssetHandle.fromRepoPath("game:materials/uv_grid.mat").?}),
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

            if (other.behavior != .planet) {
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

                const force_mag: f32 = (GRAVITATION_CONST * entity_mass * other_mass) / (distance * distance);
                if (force_mag > 0.0001) {
                    const force = zm.splat(zm.Vec, -force_mag) * dir;
                    entity.rigid_body.body.addForce(zm.vecToArr3(force), true);
                }
            }
        }
    }

    pub fn updateShip(self: *Self, entity: *Entity, input: *PlatformInput) void {

        //Linear Movement
        {
            const thust_n = 1000000.0;

            const x_axis_input = getControllerAxis(input, .left_x);
            const y_axis_input = getControllerButtonAxis(input, .right_shoulder, .left_shoulder);
            const z_axis_input = getControllerAxis(input, .left_y);

            if (@abs(x_axis_input) > 0.1 or @abs(y_axis_input) > 0.1 or @abs(z_axis_input) > 0.1) {
                const vec_input: zm.Vec = .{ x_axis_input, y_axis_input, z_axis_input, 0.0 };
                const relative_force: zm.Vec = vec_input * zm.splat(zm.Vec, thust_n);
                const force = zm.rotate(entity.transform.rotation, relative_force);
                entity.rigid_body.body.addForce(zm.vecToArr3(force), true);
                std.log.info("Adding Force: {any}", .{zm.vecToArr3(force)});
            }
        }

        //Angular Movement
        {
            const pitch_input = getControllerAxis(input, .right_y);
            const yaw_input = getControllerAxis(input, .right_x);
            _ = yaw_input; // autofix

            if (@abs(pitch_input) > 0.1) {
                const vec_input: zm.Vec = .{ pitch_input * 10000.0, 0.0, 0.0, 0.0 };
                const angular_impulse = zm.rotate(entity.transform.rotation, vec_input);
                entity.rigid_body.body.addTorque(zm.vecToArr3(angular_impulse), true);
            }
        }

        //Do Gravity Calculations
        self.updatePlanet(entity);
    }
};

pub fn calcOrbitalVelocity(gravity_mass: f32, radius: f32) f32 {
    return @sqrt((GRAVITATION_CONST * gravity_mass) / radius);
}

pub fn getControllerAxis(input: *PlatformInput, axis: Controller.Axis) f32 {
    const controllers = input.controllers.values();
    if (controllers.len > 0) {
        const controller = controllers[0];
        return controller.axis_state[@intFromEnum(axis)].value;
    }

    return 0.0;
}

pub fn getControllerButtonAxis(input: *PlatformInput, pos: Controller.Button, neg: Controller.Button) f32 {
    const controllers = input.controllers.values();
    if (controllers.len > 0) {
        const controller = controllers[0];
        const pos_state = controller.button_state[@intFromEnum(pos)].is_pressed;
        const neg_state = controller.button_state[@intFromEnum(neg)].is_pressed;

        if (pos_state and !neg_state) {
            return 1.0;
        } else if (!pos_state and neg_state) {
            return -1.0;
        }
    }

    return 0.0;
}
