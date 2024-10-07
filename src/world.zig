const std = @import("std");
const za = @import("zalgebra");
const Transform = @import("unscaled_transform.zig");

const physics_system = @import("physics");
const rendering_system = @import("rendering.zig");

const entities = @import("entity.zig");
const StaticEntity = entities.StaticEntity;
const DynamicEntity = entities.DynamicEntity;
const Character = entities.Character;

const ObjectPool = @import("object_pool.zig").ObjectPool;

//TODO: entites will probably need some sort of GUID
pub const EntityType = enum(u32) {
    static = 1,
    dynamic,
    character,
};
pub const EntityHandle = union(EntityType) {
    static: StaticEntityPool.Handle,
    dynamic: DynamicEntityPool.Handle,
    character: CharacterPool.Handle,

    //TODO: convert these values without ptr casting?
    const Self = @This();
    pub fn to_u64(self: Self) u64 {
        comptime std.debug.assert(@sizeOf(Self) == @sizeOf(u64));
        const ptr = &self;
        const u64_ptr: *const u64 = @alignCast(@ptrCast(ptr));
        return u64_ptr.*;
    }
    pub fn from_u64(value: u64) Self {
        const u64_ptr = &value;
        const ptr: *const Self = @alignCast(@ptrCast(u64_ptr));
        return ptr.*;
    }
};
pub const Entity = union(EntityType) {
    static: StaticEntity,
    dynamic: DynamicEntity,
    character: Character,
};
pub const EntityPtr = union(EntityType) {
    static: *StaticEntity,
    dynamic: *DynamicEntity,
    character: *Character,
};

pub const StaticEntityPool = ObjectPool(u16, StaticEntity);
pub const DynamicEntityPool = ObjectPool(u16, DynamicEntity);
pub const CharacterPool = ObjectPool(u16, Character);

//TODO: define what layers should collide with other layers
pub const PhysicsLayer = packed struct(physics_system.ObjectLayer) {
    static: bool = false,
    dynamic: bool = false,
    gravity: bool = false,
    padding: u13 = 0,
};

pub const RayCastHit = struct {
    entity_handle: EntityHandle,
    shape_index: u32 = 0,
    distance: f32,
    ws_position: za.Vec3,
    ws_normal: za.Vec3,
};

pub const ShapeCastHit = struct {
    entity_handle: EntityHandle,
    shape_index: u32 = 0,
};
pub const ShapeCastHitList = std.ArrayList(ShapeCastHit);

pub const World = struct {
    const Self = @This();

    physics_world: physics_system.World,
    rendering_world: rendering_system.Scene,

    static_entities: StaticEntityPool,
    dynamic_entities: DynamicEntityPool,
    characters: CharacterPool,

    pub fn init(
        allocator: std.mem.Allocator,
        backend: *rendering_system.Backend,
    ) Self {
        return .{
            .physics_world = physics_system.World.init(.{}),
            .rendering_world = backend.create_scene(),

            .static_entities = StaticEntityPool.init(allocator),
            .dynamic_entities = DynamicEntityPool.init(allocator),
            .characters = CharacterPool.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.static_entities.deinit_with_entries();
        self.dynamic_entities.deinit_with_entries();
        self.characters.deinit_with_entries();

        self.physics_world.deinit();
        self.rendering_world.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) void {
        {
            var iter = self.dynamic_entities.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.pre_physics_update(self, delta_time);
            }
        }

        {
            var iter = self.characters.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.pre_physics_update(self, delta_time);
            }
        }

        self.physics_world.update(delta_time, 1);

        {
            var iter = self.dynamic_entities.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.post_physics_update(self);
            }
        }

        {
            var iter = self.characters.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.post_physics_update(self);
            }
        }
    }

    pub fn add(self: *Self, comptime entity_type: type, entity: entity_type) !EntityHandle {
        const entity_handle: EntityHandle = switch (entity_type) {
            StaticEntity => .{ .static = try self.static_entities.insert(entity) },
            DynamicEntity => .{ .dynamic = try self.dynamic_entities.insert(entity) },
            Character => .{ .character = try self.characters.insert(entity) },
            else => @compileError("Invalid Entity Type"),
        };

        //Get the ptr and add to world with the id.
        switch (self.get_ptr(entity_handle).?) {
            .static => |ptr| try ptr.add_to_world(entity_handle, self),
            .dynamic => |ptr| try ptr.add_to_world(entity_handle, self),
            .character => |ptr| try ptr.add_to_world(entity_handle, self),
        }

        return entity_handle;
    }

    pub fn add_enum_entity(self: *Self, entity: Entity) !EntityHandle {
        return switch (entity) {
            .static => |static| try self.add(StaticEntity, static),
            .dynamic => |dynamic| try self.add(DynamicEntity, dynamic),
            .character => |character| try self.add(Character, character),
        };
    }

    pub fn remove(self: *Self, handle: EntityHandle) ?Entity {
        var entity_opt: ?Entity = switch (handle) {
            .static => |static_handle| if (self.static_entities.remove(static_handle)) |entity| .{ .static = entity } else null,
            .dynamic => |dynamic_handle| if (self.dynamic_entities.remove(dynamic_handle)) |entity| .{ .dynamic = entity } else null,
            .character => |character_handle| if (self.characters.remove(character_handle)) |entity| .{ .character = entity } else null,
        };

        if (entity_opt) |*entity| {
            switch (entity.*) {
                .static => |*static| static.remove_from_world(self),
                .dynamic => |*dynamic| dynamic.remove_from_world(self),
                .character => |*character| character.remove_from_world(self),
            }
        }
        return entity_opt;
    }

    pub fn get_ptr(self: *Self, handle: EntityHandle) ?EntityPtr {
        return switch (handle) {
            .static => |static_handle| if (self.static_entities.getPtr(static_handle)) |ptr| .{ .static = ptr } else null,
            .dynamic => |dynamic_handle| if (self.dynamic_entities.getPtr(dynamic_handle)) |ptr| .{ .dynamic = ptr } else null,
            .character => |character_handle| if (self.characters.getPtr(character_handle)) |ptr| .{ .character = ptr } else null,
        };
    }

    fn ray_hit_convert(hit: physics_system.RayCastHit) RayCastHit {
        return .{
            .entity_handle = EntityHandle.from_u64(hit.body_user_data),
            .shape_index = hit.shape_index,
            .distance = hit.distance,
            .ws_position = za.Vec3.fromArray(hit.ws_position),
            .ws_normal = za.Vec3.fromArray(hit.ws_normal),
        };
    }

    pub fn ray_cast(
        self: Self,
        physics_layer: PhysicsLayer,
        start: za.Vec3,
        direction: za.Vec3,
    ) ?RayCastHit {
        if (self.physics_world.ray_cast_closest(@bitCast(physics_layer), start.toArray(), direction.toArray())) |hit| {
            return ray_hit_convert(hit);
        }

        return null;
    }

    pub fn ray_cast_ignore(
        self: Self,
        physics_layer: PhysicsLayer,
        ignore_entity: EntityHandle,
        start: za.Vec3,
        direction: za.Vec3,
    ) ?RayCastHit {
        const entity_ptr_opt = self.get_ptr(ignore_entity);

        if (entity_ptr_opt) |entity_ptr| {
            switch (entity_ptr) {
                .character => |character| {
                    if (self.physics_world.ray_cast_closest_ignore_character(@bitCast(physics_layer), character.physics.?, start.toArray(), direction.toArray())) |hit| {
                        return ray_hit_convert(hit);
                    }
                },
                else => unreachable,
            }

            return null;
        } else {
            return self.ray_cast(physics_layer, start, direction);
        }

        return null;
    }

    pub fn shape_cast(self: *Self, temp_allocator: std.mem.Allocator, physics_layer: PhysicsLayer, shape: physics_system.Shape, transform: Transform) ?ShapeCastHitList {
        var callback_list = ShapeCastHitList.init(temp_allocator);
        self.physics_world.shape_cast(@bitCast(physics_layer), shape, &.{ .position = transform.position.toArray(), .rotation = transform.rotation.toArray() }, &shape_cast_callback, &callback_list);

        if (callback_list.items.len == 0) {
            callback_list.deinit();
            return null;
        }

        return callback_list;
    }
};

fn shape_cast_callback(ptr_opt: ?*anyopaque, hit: physics_system.ShapeCastHit) callconv(.C) void {
    if (ptr_opt) |ptr| {
        const callback_list: *ShapeCastHitList = @alignCast(@ptrCast(ptr));
        callback_list.append(.{
            .entity_handle = EntityHandle.from_u64(hit.body_user_data),
            .shape_index = hit.shape_index,
        }) catch |err| {
            std.log.err("Failed to append shape cast hit {}", .{err});
        };
    }
}
