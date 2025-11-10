const std = @import("std");

const zm = @import("zmath");

const AssetRegistry = @import("../asset/registry.zig");
const Transform = @import("../transform.zig");
const Resources = @import("resources.zig");
const UnifiedGeometryBuffer = @import("unified_geometry_buffer.zig");
const Backend = @import("vulkan/backend.zig");

pub const MaterialArray = struct {
    const BufferSize = 32;

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
    visable: u32,
    material_indexes: [MaxPrimitives]u32,
};

pub const RenderData = struct {
    instance_count: u32,
    instance_buffer: Backend.BufferHandle,
};

const Self = @This();

allocator: std.mem.Allocator,
instances: std.ArrayList(SceneMesh) = .empty,

instance_count: usize = 0,
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
    return self.instance_count * MaxPrimitives;
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
        var gpu_instances: std.ArrayList(GpuInstace) = try .initCapacity(temp_allocator, self.instances.items.len);
        defer gpu_instances.deinit(temp_allocator);

        for (self.instances.items) |instance| {
            const model_matrix = instance.transform.getModelMatrix();
            const mesh = resources.meshes.map.get(instance.component.mesh) orelse continue;
            const material_slice = instance.component.materials.constSlice();

            var primitive_offset: usize = 0;

            while (primitive_offset < material_slice.len) {
                var material_indexes: [MaxPrimitives]u32 = std.mem.zeroes([MaxPrimitives]u32);
                const primitive_count: usize = @min(material_slice.len - primitive_offset, MaxPrimitives);

                for (material_slice[primitive_offset..(primitive_offset + primitive_count)], 0..) |material, i| {
                    material_indexes[i] = if (resources.material_map.get(material)) |mat| mat.buffer_index orelse 0 else 0;
                }

                try gpu_instances.append(temp_allocator, .{
                    .model_matrix = model_matrix,
                    .mesh_index = mesh.index,
                    .primitive_offset = @intCast(primitive_offset),
                    .primitive_count = @intCast(primitive_count),
                    .visable = @intFromBool(instance.component.visable),
                    .material_indexes = material_indexes,
                });
                primitive_offset += primitive_count;
            }
        }

        self.instance_count = gpu_instances.items.len;
        self.instance_buffer = backend.createBufferWithData(
            "scene_instance_buffer",
            .{ .storage_buffer_bit = true },
            std.mem.sliceAsBytes(gpu_instances.items),
        ) catch null;
    }
}
