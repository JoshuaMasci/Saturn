const std = @import("std");

const zm = @import("zmath");

const zjolt = @import("zjolt");

const Transform = @import("transform.zig");
const Camera = @import("rendering/camera.zig").Camera;
const RenderScene = @import("rendering/scene.zig");

pub const ObjectLayers = packed struct(u16) {
    static: bool = false,
    dynamic: bool = false,
    player: bool = false,
    _pad0: u13 = 0,

    pub fn toU16(self: ObjectLayers) u16 {
        return @bitCast(self);
    }

    pub fn fromU16(value: u16) ObjectLayers {
        return @bitCast(value);
    }
};

pub const Entity = struct {
    handle: EntityHandle,

    name: ?[:0]const u8 = null,
    transform: Transform = .Identity,

    components: struct {
        static_mesh: ?RenderScene.StaticMeshInstanceHandle = null,
        rigid_body: ?zjolt.BodyID = null,
        camera: ?Camera = null,
    } = .{},
};
pub const EntityHandle = u64;

const Self = @This();

gpa: std.mem.Allocator,

next_handle: EntityHandle = 1,
entities: std.ArrayList(Entity) = .empty,

components: struct {
    rendering: ?RenderScene = null,
    physics: ?zjolt.World = null,
} = .{},

pub fn init(gpa: std.mem.Allocator) Self {
    return .{
        .gpa = gpa,
    };
}

pub fn deinit(self: *Self) void {
    for (self.entities.items) |*entity| {
        if (entity.name) |name| self.gpa.free(name);
    }

    self.entities.deinit(self.gpa);

    if (self.components.rendering) |*scene| scene.deinit();
    if (self.components.physics) |*world| world.deinit();
}

pub fn update(self: *Self, dt: f32) void {
    if (self.components.rendering) |*scene| {
        for (self.entities.items) |*entity| {
            if (entity.components.static_mesh) |static_mesh| {
                scene.updateStaticMeshInstance(static_mesh, true, entity.transform);
            }
        }
    }

    if (self.components.physics) |*physics| {
        for (self.entities.items) |*entity| {
            if (entity.components.rigid_body) |rigid_body| {
                physics.setBodyPositionAndRotationWhenChanged(rigid_body, &.{
                    .position = zm.vecToArr3(entity.transform.position),
                    .rotation = zm.vecToArr4(entity.transform.rotation),
                }, .dont_activate);
            }
        }

        physics.update(dt, 1) catch |err| std.log.err("Failed to update physics world {}", .{err});

        for (self.entities.items) |*entity| {
            if (entity.components.rigid_body) |rigid_body| {
                if (physics.getBodyMotionType(rigid_body) == .dynamic) {
                    const rigid_body_transform = physics.getBodyPositionAndRotation(rigid_body);
                    entity.transform.position = zm.loadArr3(rigid_body_transform.position);
                    entity.transform.rotation = zm.loadArr4(rigid_body_transform.rotation);
                }
            }
        }
    }
}

fn findEntityIndex(self: *const Self, handle: EntityHandle) ?usize {
    for (self.entities.items, 0..) |entity, i| {
        if (entity.handle == handle) {
            return i;
        }
    }
    return null;
}

pub fn createEntity(self: *Self, name_opt: ?[]const u8, transform: Transform) error{OutOfMemory}!EntityHandle {
    const handle = self.next_handle;
    const name: ?[:0]const u8 = if (name_opt) |name| try self.gpa.dupeZ(u8, name) else null;
    try self.entities.append(self.gpa, .{
        .handle = handle,
        .name = name,
        .transform = transform,
    });
    self.next_handle += 1;
    return handle;
}

pub fn removeEntity(self: *Self, handle: EntityHandle) void {
    const index_of = self.getEntity(handle) orelse return;

    const entity: *Entity = &self.entities.items[index_of];
    //Delete stuff here
    if (entity.name) |name| self.gpa.free(name);
    if (entity.components.static_mesh) |static_mesh| {
        _ = static_mesh; // autofix
        if (self.components.rendering) |*scene| {
            _ = scene; // autofix
            //scene.destroyStaticMesh(static_mesh);
        }
    }

    if (entity.components.rigid_body) |body_id| {
        if (self.components.physics) |*physics| {
            physics.destroyBody(body_id);
        }
    }

    self.entities.swapRemove(index_of);
}

pub fn getEntity(self: *Self, handle: EntityHandle) ?*Entity {
    const index_of = self.findEntityIndex(handle) orelse return null;
    return &self.entities.items[index_of];
}
