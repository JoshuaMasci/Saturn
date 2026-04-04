const std = @import("std");

const zm = @import("zmath");

const Transform = @import("../transform.zig");
const AssetPool = @import("asset_pool.zig");

const InstanceMap = @import("../containers.zig").SlotMap(Instance);
pub const InstanceHandle = InstanceMap.Handle;

pub const Instance = struct {
    pub const Primitive = struct {
        material: AssetPool.MaterialAssetHandle,
    };

    visable: bool,
    transform: Transform,
    mesh: AssetPool.MeshAssetHandle,
    primitives: []Primitive,
};

const Self = @This();

gpa: std.mem.Allocator,
instances: InstanceMap,

pub fn init(gpa: std.mem.Allocator) Self {
    return Self{
        .gpa = gpa,
        .instances = .init(gpa),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.instances.iterator();
    while (iter.nextValue()) |instance| {
        self.gpa.free(instance.primitives);
    }

    self.instances.deinit();
}

pub fn addInstance(self: *Self, visable: bool, transform: Transform, mesh: AssetPool.MeshAssetHandle, materials: []const AssetPool.MaterialAssetHandle) error{OutOfMemory}!InstanceHandle {
    const primitives: []Instance.Primitive = try self.gpa.alloc(Instance.Primitive, materials.len);
    errdefer self.gpa.free(primitives);

    for (primitives, materials) |*primitive, material| {
        primitive.material = material;
    }

    return try self.instances.insert(Instance{
        .visable = visable,
        .transform = transform,
        .mesh = mesh,
        .primitives = primitives,
    });
}

pub fn removeInstance(self: *Self, handle: InstanceHandle) void {
    if (self.instances.remove(handle)) |instance| {
        self.gpa.free(instance.primitives);
    }
}
