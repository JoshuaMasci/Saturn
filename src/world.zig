const std = @import("std");
const zm = @import("zmath");
const object_pool = @import("object_pool.zig");
const Transform = @import("transform.zig");

const physics_system = @import("physics.zig");
const rendering_system = @import("rendering.zig");

pub const Entity = struct {
    transform: Transform,
    body: ?physics_system.BodyHandle,
    instance: ?rendering_system.SceneInstanceHandle,
};

pub const World = struct {
    const Self = @This();
    const EntityPool = object_pool.ObjectPool(u16, Entity);

    entities: EntityPool,
    physics_world: physics_system.World,
    rendering_world: rendering_system.Scene,

    pub fn init(
        allocator: std.mem.Allocator,
        backend: *rendering_system.Backend,
    ) Self {
        return .{
            .entities = EntityPool.init(allocator),
            .physics_world = physics_system.World.init(allocator, .{}) catch |err| {
                std.debug.panic("Failed to create physics world: {}", .{err});
            },
            .rendering_world = backend.create_scene(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit_with_entries();
        self.physics_world.deinit();
        self.rendering_world.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) void {
        {
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.body) |body_handle| {
                    var body = self.physics_world.get_body(body_handle);
                    body.set_transform(entry.value_ptr.transform.get_physics_transform());
                }
            }
        }

        self.physics_world.update(delta_time) catch |err| {
            std.log.err("Failed to update physics world: {}", .{err});
        };

        {
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.body) |body_handle| {
                    var body = self.physics_world.get_body(body_handle);
                    entry.value_ptr.transform.position = body.get_position();
                    entry.value_ptr.transform.rotation = body.get_rotation();
                }
            }
        }

        {
            var iter = self.entities.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.instance) |instance_handle| {
                    self.rendering_world.update_instance(instance_handle, &entry.value_ptr.transform);
                }
            }
        }
    }

    pub fn add_entity(
        self: *Self,
        transform: *Transform,
        rigid_body_opt: ?u32,
        model_opt: ?struct { mesh: rendering_system.StaticMeshHandle, material: rendering_system.MaterialHandle },
    ) !EntityPool.Handle {
        var body: ?physics_system.BodyHandle = null;
        if (rigid_body_opt) |rigid_body| {
            _ = rigid_body; // autofix

            const shape_settings = try physics_system.create_box(zm.loadArr3(.{ 1.0, 1.0, 1.0 }));
            defer shape_settings.release();

            const shape = try shape_settings.createShape();
            defer shape.release();

            body = try self.physics_world.create_body(transform.get_physics_transform(), shape, .dynamic);
        }

        var instance: ?rendering_system.SceneInstanceHandle = null;
        if (model_opt) |model| {
            instance = try self.rendering_world.add_instace(model.mesh, model.material, transform);
        }

        return try self.entities.insert(.{
            .transform = transform.*,
            .body = body,
            .instance = instance,
        });
    }
};

//TODO: use this later?
// pub const NodePool = object_pool.ObjectPool(u16, Node);
// pub const NodeHandle = NodePool.Handle;

// pub const NodeComponents = struct {
//     model: ?void,
//     collider: ?void,
// };

// pub const Node = struct {
//     name: ?[]const u8,
//     local_transform: Transform,
//     components: NodeComponents,

//     parent: ?NodeHandle,
//     childen: std.ArrayList(NodeHandle),
// };

// pub const EntityComponents = struct {
//     character: ?void,
//     rigid_body: ?void,
// };

// pub const EntityData = struct {
//     name: ?[]const u8,
//     transform: Transform,
//     components: EntityComponents,

//     root_nodes: std.ArrayList(NodeHandle),
//     node_pool: NodePool,
// };

// pub const EntitySystems = struct {};
// pub const Entity = struct {
//     data: EntityData,
//     systems: EntitySystems,
// };

// pub const WorldData = struct {};

// pub const World = struct {
//     data: WorldData,
//     entity_pool: std.ArrayList(?Entity),
// };
