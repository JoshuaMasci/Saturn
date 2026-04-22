const std = @import("std");

const zm = @import("zmath");

const Transform = @import("transform.zig");
const Camera = @import("rendering/camera.zig").Camera;
const RenderScene = @import("rendering/scene.zig");

pub const Entity = struct {
    handle: EntityHandle,

    name: ?[:0]const u8 = null,
    transform: Transform = .Identity,

    components: struct {
        static_mesh: ?RenderScene.StaticMeshInstanceHandle = null,
        camera: ?Camera = null,
    } = .{},
};
pub const EntityHandle = u64;

const Self = @This();

gpa: std.mem.Allocator,

next_handle: EntityHandle = 1,
entities: std.ArrayList(Entity) = .empty,

components: struct {
    scene: ?RenderScene = null,
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

    if (self.components.scene) |*scene| scene.deinit();
}

pub fn update(self: *Self, dt: f32) void {
    _ = dt; // autofix
    for (self.entities.items) |*entity| {
        if (entity.components.static_mesh) |static_mesh| {
            if (self.components.scene) |*scene| {
                scene.updateStaticMeshInstance(static_mesh, true, entity.transform);
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
        if (self.components.scene) |*scene| {
            _ = scene; // autofix
            //scene.destroyStaticMesh(static_mesh);
        }
    }

    self.entities.swapRemove(index_of);
}

pub fn getEntity(self: *Self, handle: EntityHandle) ?*Entity {
    const index_of = self.findEntityIndex(handle) orelse return null;
    return &self.entities.items[index_of];
}
