const std = @import("std");

const zm = @import("zmath");

const Backend = @import("vulkan/backend.zig");

const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");

const InstanceMap = @import("../containers.zig").HandlePool(SceneInstance);
const MaterialArray = @import("../fixed_array_list.zig").FixedArrayList(AssetRegistry.Handle, 32);

pub const SceneInstanceHandle = InstanceMap.Handle;
pub const SceneInstance = struct {
    transform: Transform,
    visable: bool = true,
    mesh: AssetRegistry.Handle,
    materials: MaterialArray,
};

const Self = @This();

// CPU
allocator: std.mem.Allocator,
instances: InstanceMap,

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

pub fn addInstance(self: *Self, instance: SceneInstance) SceneInstanceHandle {
    return self.instances.insert(instance) catch @panic("Failed to appened to instances");
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
