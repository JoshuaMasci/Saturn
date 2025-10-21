const std = @import("std");

const zm = @import("zmath");

const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");
const Resources = @import("resources.zig");
const UnifiedGeometryBuffer = @import("unified_geometry_buffer.zig");
const Backend = @import("vulkan/backend.zig");

pub const MaterialArray = struct {
    const BufferSize = 8;

    buffer: [BufferSize]AssetRegistry.Handle,
    len: usize,

    pub fn init() MaterialArray {
        return .{ .buffer = undefined, .len = 0 };
    }

    pub fn fromSlice(src: []const AssetRegistry.Handle) MaterialArray {
        std.debug.assert(src.len <= BufferSize);
        var buffer: [BufferSize]AssetRegistry.Handle = .{AssetRegistry.Handle{ .repo_hash = 0, .asset_hash = 0 }} ** BufferSize;
        std.mem.copyForwards(AssetRegistry.Handle, &buffer, src);

        return .{
            .buffer = buffer,
            .len = src.len,
        };
    }

    pub fn constSlice(self: *const MaterialArray) []const AssetRegistry.Handle {
        return self.buffer[0..self.len];
    }
};

pub const StaticMeshComponent = struct {
    visable: bool = true,
    mesh: AssetRegistry.Handle,
    materials: MaterialArray,
};

pub const SceneMesh = struct {
    transform: Transform,
    component: StaticMeshComponent,
};

pub const MaxPrimitives = 8;
pub const GpuInstace = struct {
    model_matrix: zm.Mat,
    mesh_index: u32,
    primitive_offset: u32,
    primitive_count: u32,
    pad0: u32 = 0,
    material_indexes: [MaxPrimitives]u32,
};

pub const RenderData = struct {
    instance_count: u32,
    instance_buffer: Backend.BufferHandle,
};

const Self = @This();

allocator: std.mem.Allocator,
instances: std.ArrayList(SceneMesh) = .empty,
instance_buffer: ?Backend.BufferHandle = null,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self, backend: *Backend) void {
    self.instances.deinit(self.allocator);
    if (self.instance_buffer) |buffer| {
        backend.destroyBuffer(buffer);
    }
}

pub fn addInstance(self: *Self, mesh: SceneMesh) void {
    self.instances.append(self.allocator, mesh) catch @panic("Failed to appened to instances");
}

pub fn getIndirectDrawCount(self: Self) usize {
    return self.instances.items.len * MaxPrimitives;
}

pub fn update(
    self: *Self,
    temp_allocator: std.mem.Allocator,
    backend: *Backend,
    resources: *const Resources,
) !void {
    if (self.instance_buffer) |buffer| {
        backend.destroyBuffer(buffer);
    }

    if (self.instances.items.len != 0) {
        var gpu_index: u32 = 0;
        var gpu_instances = try temp_allocator.alloc(GpuInstace, self.instances.items.len);
        defer temp_allocator.free(gpu_instances);

        for (self.instances.items) |instance| {
            const mesh = resources.meshes.map.get(instance.component.mesh) orelse continue;
            var material_indexes: [8]u32 = undefined;
            for (instance.component.materials.constSlice(), 0..) |material, i| {
                material_indexes[i] = if (resources.material_map.get(material)) |mat| mat.buffer_index orelse 0 else 0;
            }

            gpu_instances[gpu_index] = .{
                .model_matrix = instance.transform.getModelMatrix(),
                .mesh_index = mesh.index,
                .primitive_offset = 0,
                .primitive_count = @intCast(mesh.cpu_primitives.len),
                .material_indexes = material_indexes,
            };
            gpu_index += 1;
        }
        self.instance_buffer = backend.createBufferWithData(
            "scene_instance_buffer",
            .{ .storage_buffer_bit = true },
            std.mem.sliceAsBytes(gpu_instances),
        ) catch null;
    }
}
