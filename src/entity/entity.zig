const std = @import("std");
const World = @import("world.zig");

const Universe = @import("universe.zig");
const UpdateStage = Universe.UpdateStage;

const Transform = @import("../transform.zig");
const utils = @import("../utils.zig");

const EntitySystem = @import("entity_system.zig");

pub const Handle = u64;

const Self = @This();

//TODO: heap alloc name
name: ?[]const u8 = null,

handle: Handle,
universe: *Universe,
world: ?*World = null,
transform: Transform = .{},
systems: EntitySystem.Systems,

root: *Self = undefined,
parent: ?*Self = null,
children: std.AutoArrayHashMap(Handle, *Self),

//TODO: cache values
//Transform caches
//cached_root_transform: ?Transform = null,
//cached_world_transform: ?Transform = null,

pub fn init(allocator: std.mem.Allocator, universe: *Universe, handle: Handle, name: ?[]const u8) Self {
    return .{
        .name = name,
        .universe = universe,
        .handle = handle,
        .systems = EntitySystem.Systems.init(allocator),
        .children = std.AutoArrayHashMap(Handle, *Self).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.children.deinit();

    // if (self.name) |name| {
    //     name.deinit();
    // }
    self.systems.deinit();
}

pub fn addChild(self: *Self, child: *Self) void {
    std.debug.assert(child.parent == null);
    std.debug.assert(!self.children.contains(child.handle));

    child.parent = self;
    child.setHierarchyRoot(self.root);
    self.children.put(child.handle, child) catch |err| std.debug.panic("Failed to append child: {}", .{err});

    if (self.world) |world| {
        world.addEntity(child);
    }
}

pub fn removeChild(self: *Self, handle: Handle) void {
    const result = self.children.fetchSwapRemove(handle);
    if (result) |child| {
        if (child.value.world) |world| {
            world.removeEntity(child);
        }

        child.value.setHierarchyRoot(child.value);
        child.value.parent = null;
    }
}

fn setHierarchyRoot(self: *Self, root: *Self) void {
    self.root = root;
    for (self.children.values()) |child| {
        child.setHierarchyRoot(root);
    }
}

pub fn getRootTransform(self: *const Self) Transform {
    if (self.parent) |parent| {
        return parent.getRootTransform().applyTransform(&self.transform);
    } else {
        return .{};
    }
}

pub fn getWorldTransform(self: *const Self) Transform {
    if (self.parent) |parent| {
        return parent.getWorldTransform().applyTransform(&self.transform);
    } else {
        return self.transform;
    }
}

pub fn updateParallel(self: *Self, stage: UpdateStage, delta_time: f32) void {
    self.systems.updateParallel(stage, self, delta_time);

    //TODO: allow removal during loop?
    for (self.children.values()) |child| {
        child.updateParallel(stage, delta_time);
    }
}

pub fn updateExclusive(self: *Self, stage: UpdateStage, delta_time: f32) void {
    self.systems.updateExclusive(stage, self, delta_time);

    for (self.children.values()) |child| {
        child.updateExclusive(stage, delta_time);
    }
}

//TODO: Implement this in world update scheduling
pub const UpdateMode = enum {
    // Update every frame both in parallel pass and exclusive lock on the world
    exclusive_and_parallel,

    // Update every frame in parallel with other entities, world is const
    parallel,

    // Never runs update, used for static objects
    never,
};
