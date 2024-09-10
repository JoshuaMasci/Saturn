const std = @import("std");
const za = @import("zalgebra");
const Transform = @import("unscaled_transform.zig");

const physics_system = @import("physics");
const rendering_system = @import("rendering.zig");

const entity_zig = @import("entity.zig");
const StaticEntity = entity_zig.StaticEntity;
const DynamicEntity = entity_zig.DynamicEntity;

const ObjectPool = @import("object_pool.zig").ObjectPool;

pub const EntityHandle = union(enum(u32)) {
    static: StaticEntityPool.Handle,
    dynamic: DynamicEntityPool.Handle,
    character: CharacterPool.Handle,

    pub fn to_u64(self: @This()) u64 {
        _ = self; // autofix
        comptime std.debug.assert(@sizeOf(@This()) == @sizeOf(u64));
        return 0;
    }
};

pub const StaticEntityPool = ObjectPool(u16, StaticEntity);
pub const DynamicEntityPool = ObjectPool(u16, DynamicEntity);
pub const CharacterPool = ObjectPool(u16, void);

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
                entry.value_ptr.*.pre_physics_update(self);
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
                _ = entry;
            }
        }
    }

    pub fn add(self: *Self, comptime entity_type: type, entity: entity_type) !EntityHandle {
        var entity_clone: entity_type = entity;
        try entity_clone.add_to_world(self);

        return switch (entity_type) {
            StaticEntity => .{ .static = try self.static_entities.insert(entity_clone) },
            DynamicEntity => .{ .dynamic = try self.dynamic_entities.insert(entity_clone) },
            else => @compileError("Invalid Entity Type"),
        };
    }
};
