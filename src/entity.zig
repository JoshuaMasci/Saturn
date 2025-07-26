const std = @import("std");

const zm = @import("zmath");

const Transform = @import("transform.zig");

const jolt = @import("physics");
const rendering_scene = @import("rendering/scene.zig");

pub const Componets = struct {
    mesh: ?rendering_scene.StaticMeshComponent = null,
    rigid_body: ?RigidBodyComponent = null,
    lua_script: ?void = null,
};

pub const Entity = struct {
    const Self = @This();

    name: ?[]const u8 = null,
    transform: Transform = .{},
    components: Componets = .{},
};

pub const Systems = struct {
    rendering: ?RenderingSystem = null,
    physics: ?PhysicsSystem = null,
    lua: ?LuaSystem = null,
};

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    entities: std.ArrayList(*Entity),
    systems: Systems,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, systems: Systems) !Self {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .entities = .init(allocator),
            .systems = systems,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);

        for (self.entities.items) |entity| {
            if (entity.name) |name| {
                self.allocator.free(name);
            }
        }
        self.entities.deinit();

        if (self.systems.rendering) |*rendering| {
            rendering.deinit();
        }

        if (self.systems.physics) |*physics| {
            physics.deinit();
        }

        if (self.systems.lua) |*lua| {
            lua.deinit();
        }
    }

    pub fn update(self: *Self, delta_time: f32) void {
        if (self.systems.lua) |*lua| {
            lua.update(self, delta_time);
        }

        if (self.systems.physics) |*physics| {
            physics.update(self, delta_time);
        }

        if (self.systems.rendering) |*rendering| {
            rendering.update(self, delta_time);
        }
    }
};

pub const RenderingSystem = struct {
    const Self = @This();

    scene: rendering_scene.RenderScene,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .scene = rendering_scene.RenderScene.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.scene.deinit();
    }

    pub fn registerEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix
        _ = entity; // autofixs
        _ = self; // autofix
    }

    pub fn deregisterEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix
        _ = entity; // autofix
        _ = self; // autofix
    }

    pub fn update(self: *Self, world: *World, delta_time: f32) void {
        _ = delta_time; // autofix

        self.scene.clear();

        for (world.entities.items) |entity| {
            if (entity.components.mesh) |mesh| {
                self.scene.static_meshes.append(.{
                    .transform = entity.transform,
                    .component = mesh,
                }) catch |err| std.log.err("Failed to append mesh to scene {}", .{err});
            }
        }
    }
};

pub const RigidBodyComponent = struct {
    body: jolt.Body,
    linear_velocity: zm.Vec = zm.splat(zm.Vec, 0.0),
    angular_velocity: zm.Vec = zm.splat(zm.Vec, 0.0),
};

pub const Collider = struct {
    collider: jolt.Shape,
};

pub const PhysicsSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    physics_world: jolt.World,
    bodies: std.ArrayListUnmanaged(*Entity),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .physics_world = jolt.World.init(.{}),
            .bodies = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.bodies.deinit(self.allocator);
        self.physics_world.deinit();
    }

    pub fn registerEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofixs

        if (entity.components.rigid_body) |rigid_body| {
            rigid_body.setTransform(&.{
                .position = zm.vecToArr3(entity.transform.position),
                .rotation = zm.vecToArr4(zm.normalize4(entity.transform.rotation)),
            });
            rigid_body.setVelocity(&.{
                .linear = zm.vecToArr3(rigid_body.linear_velocity),
                .angular = zm.vecToArr3(rigid_body.angular_velocity),
            });
            self.physics_world.addBody(rigid_body.body);
            self.bodies.append(self.allocator, entity) catch |err| std.log.err("Failed to append mesh to physics body list {}", .{err});
        }
    }

    pub fn deregisterEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix

        if (entity.components.rigid_body) |rigid_body| {
            self.physics_world.removeBody(rigid_body.body);

            for (self.bodies.items, 0..) |item, i| {
                if (item == entity) {
                    _ = self.bodies.swapRemove(i);
                    break;
                }
            }
        }
    }

    pub fn update(self: *Self, world: *World, delta_time: f32) void {
        _ = world; // autofix

        //Pre Physics
        for (self.bodies.items) |entity| {
            if (entity.components.rigid_body) |*rigid_body| {
                rigid_body.body.setTransform(&.{
                    .position = zm.vecToArr3(entity.transform.position),
                    .rotation = zm.vecToArr4(zm.normalize4(entity.transform.rotation)),
                });
                rigid_body.body.setVelocity(&.{
                    .linear = zm.vecToArr3(rigid_body.linear_velocity),
                    .angular = zm.vecToArr3(rigid_body.angular_velocity),
                });
            }
        }

        self.physics_world.update(delta_time, 1);

        //Post Physics
        for (self.bodies.items) |entity| {
            if (entity.components.rigid_body) |*rigid_body| {
                const transform = rigid_body.body.getTransform();
                entity.transform.position = zm.loadArr3(transform.position);
                entity.transform.rotation = zm.normalize4(zm.loadArr4(transform.rotation));

                const velocity = rigid_body.body.getVelocity();
                rigid_body.linear_velocity = zm.loadArr3(velocity.linear);
                rigid_body.angular_velocity = zm.loadArr3(velocity.angular);
            }
        }
    }
};

pub const LuaSystem = struct {
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        _ = allocator; // autofix
        return .{};
    }

    pub fn deinit(self: *Self) void {
        _ = self; // autofix
    }

    pub fn registerEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix
        _ = entity; // autofixs
        _ = self; // autofix
    }

    pub fn deregisterEntity(self: *Self, world: *World, entity: *Entity) void {
        _ = world; // autofix
        _ = entity; // autofix
        _ = self; // autofix
    }

    pub fn update(self: *Self, world: *World, delta_time: f32) void {
        _ = delta_time; // autofix
        _ = self; // autofix
        _ = world; // autofix
    }
};
