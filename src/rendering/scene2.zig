const std = @import("std");

const zm = @import("zmath");

const Backend = @import("vulkan/backend.zig");

const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");

const InstanceMap = @import("../containers.zig").HandlePool(SceneInstance);
const FixedArrayList = @import("../fixed_array_list.zig").FixedArrayList;

const MaxPrimitives: comptime_int = 32;
const PrimitiveArray = FixedArrayList(ScenePrimitive, MaxPrimitives);

pub const SceneInstanceHandle = InstanceMap.Handle;
const SceneInstance = struct {
    transform: Transform,
    visable: bool = true,
    mesh: AssetRegistry.Handle,

    instance_index: ?u32 = null,
    primtives: PrimitiveArray = .empty,
};
const ScenePrimitive = struct {
    material_handle: AssetRegistry.Handle,
    primitive_index_index: ?u32 = null,
};

const Self = @This();

// CPU
allocator: std.mem.Allocator,
instances: InstanceMap,

// instance_updates: struct {
//     added: std.ArrayList(SceneInstanceHandle),
//     update: std.ArrayList(SceneInstanceHandle),
//     remove: std.ArrayList(SceneInstanceHandle),
// } = .{},

// GPU
backend: *Backend,

pub fn init(allocator: std.mem.Allocator, backend: *Backend) Self {
    return .{
        .allocator = allocator,
        .instances = .init(allocator),

        .backend = backend,
    };
}

pub fn deinit(self: *Self) void {
    self.instances.deinit();
}

pub fn addInstance(
    self: *Self,
    instance: struct {
        transform: Transform,
        visable: bool = true,
        mesh: AssetRegistry.Handle,
        materials: []const AssetRegistry.Handle,
    },
) SceneInstanceHandle {
    const instance_index: u32 = 0; //TODO:

    var primitives: PrimitiveArray = .empty;

    for (instance.materials) |material| {
        primitives.add(.{
            .material_handle = material,
        });
    }

    const handle = self.instances.insert(.{
        .transform = instance.transform,
        .visable = instance.visable,
        .mesh = instance.mesh,
        .instance_index = instance_index,
        .primtives = primitives,
    }) catch @panic("Failed to appened to instances");

    return handle;
}

pub fn removeInstance(self: *Self, handle: SceneInstanceHandle) void {
    _ = self.instances.remove(handle);
}

pub fn updateInstanceTransform(self: *Self, handle: SceneInstanceHandle, transform: *Transform) void {
    if (self.instances.getPtr(handle)) |instance| {
        instance.transform = transform.*;
    } else {
        std.log.err("Invalid instance handle {}", .{handle});
    }
}
