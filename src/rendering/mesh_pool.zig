const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const Backend = @import("vulkan/backend.zig");

fn GpuBuffer(comptime T: type) type {
    return struct {
        const SubAllocation = struct {
            const Empty: @This() = .{ .offset = 0, .len = 0, .device_address = 0 };

            offset: usize,
            len: usize,
            device_address: vk.DeviceAddress,
        };

        const This = @This();

        backend: *Backend,
        buffer: Backend.BufferHandle,
        byte_slice: ?[]u8,
        device_address: vk.DeviceAddress,

        element_count: usize,
        element_offset: usize = 0,

        pub fn init(
            backend: *Backend,
            name: []const u8,
            element_count: usize,
            buffer_usage: vk.BufferUsageFlags,
        ) !This {
            const buffer = try backend.createBuffer(
                name,
                element_count * @sizeOf(T),
                buffer_usage,
            );

            const buffer_info = backend.buffers.get(buffer).?;
            const byte_slice: ?[]u8 = buffer_info.allocation.getMappedByteSlice();
            const device_address: vk.DeviceAddress = buffer_info.device_address.?;

            return .{
                .backend = backend,
                .buffer = buffer,
                .byte_slice = byte_slice,
                .device_address = device_address,
                .element_count = element_count,
            };
        }

        pub fn deinit(self: *This) void {
            self.backend.destroyBuffer(self.buffer);
        }

        pub fn alloc(self: *This, element_len: usize) error{OutOfMemory}!SubAllocation {
            if ((self.element_offset + element_len) > self.element_count) {
                return error.OutOfMemory;
            }

            defer self.element_offset += element_len;

            return SubAllocation{
                .offset = self.element_offset,
                .len = element_len,
                .device_address = self.device_address + (self.element_offset * @sizeOf(T)),
            };
        }

        pub fn write(self: *This, allocation: SubAllocation, data: []const T) !void {
            std.debug.assert(allocation.len == data.len);
            const byte_offset = allocation.offset * @sizeOf(T);
            const data_bytes = std.mem.sliceAsBytes(data);

            if (self.byte_slice) |slice| {
                @memcpy(slice[byte_offset..(byte_offset + data_bytes.len)], data_bytes);
            } else {
                try self.backend.getTransferQueue().writeBuffer(self.buffer, byte_offset, data_bytes);
            }
        }

        pub fn createBuffer(self: *This, data: []const T) !SubAllocation {
            const allocation = try self.alloc(data.len);
            errdefer self.free(allocation);
            try self.write(allocation, data);
            return allocation;
        }

        pub fn free(self: *This, allocation: SubAllocation) void {
            _ = self;
            _ = allocation;
            // NOOP: Currently implemented as a memory arena
        }

        pub fn canAlloc(self: *This, element_len: usize) bool {
            return (self.element_offset + element_len) < self.element_count;
        }
    };
}

const MeshEntry = struct {
    index: u32,
    sphere_pos_radius: [4]f32,

    cpu_primitives: []const MeshAsset.Primitive,

    vertices: GpuBuffer(MeshAsset.Vertex).SubAllocation,
    indices: GpuBuffer(u32).SubAllocation,
    primitives: GpuBuffer(MeshAsset.Primitive).SubAllocation,

    meshlet: ?struct {
        meshlets: GpuBuffer(MeshAsset.Meshlet).SubAllocation,
        meshlet_vertices: GpuBuffer(u32).SubAllocation,
        meshlet_triangles: GpuBuffer(u8).SubAllocation,
    } = null,

    fn getGpuEntry(self: MeshEntry) GpuMeshEntry {
        return .{
            .sphere_pos_radius = self.sphere_pos_radius,
            .vertex_buffer_address = self.vertices.device_address,
            .index_buffer_address = self.indices.device_address,
            .primitive_buffer_address = self.primitives.device_address,
            .meshlet_buffer_address = if (self.meshlet) |meshlet| meshlet.meshlets.device_address else 0,
            .meshlet_vertex_buffer_address = if (self.meshlet) |meshlet| meshlet.meshlet_vertices.device_address else 0,
            .meshlet_triangle_buffer_address = if (self.meshlet) |meshlet| meshlet.meshlet_triangles.device_address else 0,
            .meshlets_loaded = @intFromBool(self.meshlet != null),
        };
    }
};

const GpuMeshEntry = extern struct {
    sphere_pos_radius: [4]f32,

    vertex_buffer_address: vk.DeviceAddress,
    index_buffer_address: vk.DeviceAddress,
    primitive_buffer_address: vk.DeviceAddress,
    meshlet_buffer_address: vk.DeviceAddress,

    meshlet_vertex_buffer_address: vk.DeviceAddress,
    meshlet_triangle_buffer_address: vk.DeviceAddress,
    meshlets_loaded: u32,
    _padding: u32 = 0,
};

const MaxMeshCount: usize = 4096;

const BufferSizes = struct {
    vertices: usize,
    indices: usize,
    primitives: usize,
    meshlets: usize,
    meshlet_vertices: usize,
    meshlet_triangles: usize,

    pub fn fromTotalBytes(total_bytes: usize) BufferSizes {
        // This is possible AI nonsense, but I didn't feel like trying to calc this myself
        // Rough heuristic based on typical mesh data distribution:
        // - Vertices are usually the largest (position, normal, UV, tangent, etc.)
        // - Indices are typically 3x vertex count (3 indices per triangle)
        // - Primitives are small, roughly 1 per ~100-500 triangles
        // - Meshlets and related data take about 10-15% of total mesh data

        // Weight distribution (these should sum to approximately 1.0)
        const vertex_weight: f32 = 0.45;
        const index_weight: f32 = 0.25;
        const primitive_weight: f32 = 0.05;
        const meshlet_weight: f32 = 0.10;
        const meshlet_vertex_weight: f32 = 0.10;
        const meshlet_triangle_weight: f32 = 0.05;

        const total_f: f32 = @floatFromInt(total_bytes);

        return .{
            .vertices = @intFromFloat(total_f * vertex_weight / @sizeOf(MeshAsset.Vertex)),
            .indices = @intFromFloat(total_f * index_weight / @sizeOf(u32)),
            .primitives = @intFromFloat(total_f * primitive_weight / @sizeOf(MeshAsset.Primitive)),
            .meshlets = @intFromFloat(total_f * meshlet_weight / @sizeOf(MeshAsset.Meshlet)),
            .meshlet_vertices = @intFromFloat(total_f * meshlet_vertex_weight / @sizeOf(u32)),
            .meshlet_triangles = @intFromFloat(total_f * meshlet_triangle_weight / @sizeOf(u8)),
        };
    }

    pub fn getTotalBytes(self: BufferSizes) usize {
        var total: usize = 0;
        total += self.vertices * @sizeOf(MeshAsset.Vertex);
        total += self.indices * @sizeOf(u32);
        total += self.primitives * @sizeOf(MeshAsset.Primitive);
        total += self.meshlets * @sizeOf(MeshAsset.Meshlet);
        total += self.meshlet_vertices * @sizeOf(u32);
        total += self.meshlet_triangles * @sizeOf(u8);
        return total;
    }
};

const Self = @This();

allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

backend: *Backend,
registry: *const AssetRegistry,

vertex_buffer: GpuBuffer(MeshAsset.Vertex),
index_buffer: GpuBuffer(u32),
primitive_buffer: GpuBuffer(MeshAsset.Primitive),
meshlet_buffer: GpuBuffer(MeshAsset.Meshlet),
meshlet_vertex_buffer: GpuBuffer(u32),
meshlet_triangle_buffer: GpuBuffer(u8),

map: std.AutoArrayHashMap(AssetRegistry.AssetHandle, MeshEntry),

next_mesh_index: u32 = 0,
mesh_info_buffer: Backend.BufferHandle,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    backend: *Backend,
    buffer_sizes: BufferSizes,
) !Self {
    const geometry_buffer_usage: vk.BufferUsageFlags = .{
        .vertex_buffer_bit = true,
        .index_buffer_bit = true,
        .transfer_dst_bit = true,
        .shader_device_address_bit = true,
    };

    var vertex_buffer = try GpuBuffer(MeshAsset.Vertex).init(backend, "vertex_buffer", buffer_sizes.vertices, geometry_buffer_usage);
    errdefer vertex_buffer.deinit();

    var index_buffer = try GpuBuffer(u32).init(backend, "index_buffer", buffer_sizes.indices, geometry_buffer_usage);
    errdefer index_buffer.deinit();

    var primitive_buffer = try GpuBuffer(MeshAsset.Primitive).init(backend, "primitive_buffer", buffer_sizes.primitives, geometry_buffer_usage);
    errdefer primitive_buffer.deinit();

    var meshlet_buffer = try GpuBuffer(MeshAsset.Meshlet).init(backend, "meshlet_buffer", buffer_sizes.meshlets, geometry_buffer_usage);
    errdefer meshlet_buffer.deinit();

    var meshlet_vertex_buffer = try GpuBuffer(u32).init(backend, "meshlet_vertex_buffer", buffer_sizes.meshlet_vertices, geometry_buffer_usage);
    errdefer meshlet_vertex_buffer.deinit();

    var meshlet_triangle_buffer = try GpuBuffer(u8).init(backend, "meshlet_triangle_buffer", buffer_sizes.meshlet_triangles, geometry_buffer_usage);
    errdefer meshlet_triangle_buffer.deinit();

    const mesh_info_buffer = try backend.createBuffer(
        "mesh_info_buffer",
        @sizeOf(GpuMeshEntry) * MaxMeshCount,
        .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
    );
    errdefer backend.destroyBuffer(mesh_info_buffer);

    return .{
        .allocator = allocator,
        .arena = .init(allocator),

        .backend = backend,
        .registry = registry,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .primitive_buffer = primitive_buffer,
        .meshlet_buffer = meshlet_buffer,
        .meshlet_vertex_buffer = meshlet_vertex_buffer,
        .meshlet_triangle_buffer = meshlet_triangle_buffer,

        .map = .init(allocator),

        .mesh_info_buffer = mesh_info_buffer,
    };
}

pub fn deinit(self: *Self) void {
    self.backend.destroyBuffer(self.mesh_info_buffer);
    self.vertex_buffer.deinit();
    self.index_buffer.deinit();
    self.primitive_buffer.deinit();
    self.meshlet_buffer.deinit();
    self.meshlet_vertex_buffer.deinit();
    self.meshlet_triangle_buffer.deinit();
    self.map.deinit();
    self.arena.deinit();
}

pub fn addMesh(self: *Self, handle: AssetRegistry.AssetHandle, mesh: *const MeshAsset) !void {
    const index = self.next_mesh_index;
    self.next_mesh_index += 1;

    var entry: MeshEntry = .{
        .cpu_primitives = try self.arena.allocator().dupe(MeshAsset.Primitive, mesh.primitives),
        .index = index,
        .sphere_pos_radius = mesh.sphere_pos_radius,
        .vertices = try self.vertex_buffer.createBuffer(mesh.vertices),
        .indices = try self.index_buffer.createBuffer(mesh.indices),
        .primitives = try self.primitive_buffer.createBuffer(mesh.primitives),
        .meshlet = null,
    };

    if (mesh.meshlets.len != 0) {
        entry.meshlet = .{
            .meshlets = try self.meshlet_buffer.createBuffer(mesh.meshlets),
            .meshlet_vertices = try self.meshlet_vertex_buffer.createBuffer(mesh.meshlet_vertices),
            .meshlet_triangles = try self.meshlet_triangle_buffer.createBuffer(mesh.meshlet_triangles),
        };
    }

    try self.map.put(handle, entry);

    const entry_offset: usize = index * @sizeOf(GpuMeshEntry);
    const entry_bytes: []const u8 = std.mem.asBytes(&entry.getGpuEntry());

    if (self.backend.getBufferMappedSlice(self.mesh_info_buffer)) |mapped_slice| {
        @memcpy(mapped_slice[entry_offset..(entry_offset + entry_bytes.len)], entry_bytes);
    } else {
        try self.backend.getTransferQueue().writeBuffer(self.mesh_info_buffer, entry_offset, entry_bytes);
    }
}

pub fn canUploadMesh(self: *Self, mesh: *const MeshAsset) bool {
    // Can always upload if memory is mapped
    if (self.vertex_buffer.byte_slice != null) {
        return true;
    }

    var gpu_mesh_size: usize = 0;
    gpu_mesh_size += mesh.vertices.len * @sizeOf(MeshAsset.Vertex);
    gpu_mesh_size += mesh.indices.len * @sizeOf(u32);
    gpu_mesh_size += mesh.primitives.len * @sizeOf(MeshAsset.Primitive);
    gpu_mesh_size += mesh.meshlets.len * @sizeOf(MeshAsset.Meshlet);
    gpu_mesh_size += mesh.meshlet_vertices.len * @sizeOf(u32);
    gpu_mesh_size += mesh.meshlet_triangles.len * @sizeOf(u8);
    gpu_mesh_size += @sizeOf(GpuMeshEntry);

    const transfer_queue = self.backend.getTransferQueue();
    return transfer_queue.hasSpace(gpu_mesh_size);
}
