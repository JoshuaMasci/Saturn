const std = @import("std");

const vk = @import("vulkan");
const zm = @import("zmath");

const MeshAsset = @import("../asset/mesh.zig");
const AssetRegistry = @import("../asset/registry.zig");
const Backend = @import("vulkan/backend.zig");

const SubAllocation = struct {
    const Empty: @This() = .{ .offset = 0, .len = 0 };

    offset: usize,
    len: usize,
};

const MeshEntry = struct {
    index: u32,
    sphere_pos_radius: [4]f32,

    cpu_primitives: []const MeshAsset.Primitive,

    vertices: SubAllocation,
    indices: SubAllocation,
    primitives: SubAllocation,

    meshlet: ?struct {
        meshlets: SubAllocation = .Empty,
        meshlet_vertices: SubAllocation = .Empty,
        meshlet_triangles: SubAllocation = .Empty,
    } = null,

    fn getGpuEntry(self: MeshEntry, buffer_binding: u32) GpuMeshEntry {
        return .{
            .sphere_pos_radius = self.sphere_pos_radius,
            .buffer_binding = buffer_binding,
            .vertices_offset = @intCast(self.vertices.offset),
            .indices_offset = @intCast(self.indices.offset),
            .primitives_offset = @intCast(self.primitives.offset),
            .meshlets_loaded = @intFromBool(self.meshlet != null),
            .meshlets_offset = if (self.meshlet) |meshlet| @intCast(meshlet.meshlets.offset) else 0,
            .meshlet_vertices_offset = if (self.meshlet) |meshlet| @intCast(meshlet.meshlet_vertices.offset) else 0,
            .meshlet_triangles_offset = if (self.meshlet) |meshlet| @intCast(meshlet.meshlet_triangles.offset) else 0,
        };
    }
};

const GpuMeshEntry = extern struct {
    sphere_pos_radius: [4]f32,

    buffer_binding: u32,
    vertices_offset: u32,
    indices_offset: u32,
    primitives_offset: u32,

    meshlets_loaded: u32, //May not use this, but I needed a u32 of padding anyways
    meshlets_offset: u32,
    meshlet_vertices_offset: u32,
    meshlet_triangles_offset: u32,
};

const MaxMeshCount: usize = 4096;

const Self = @This();

allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

backend: *Backend,
registry: *const AssetRegistry,

geometry_buffer: Backend.BufferHandle,
geometry_buffer_binding: u32,
geometry_slice: ?[]u8,
buffer_size: usize,
buffer_offset: usize = 0,

map: std.AutoArrayHashMap(AssetRegistry.AssetHandle, MeshEntry),

next_mesh_index: u32 = 0,
mesh_info_buffer: Backend.BufferHandle,

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    backend: *Backend,
    buffer_size: usize,
) !Self {
    var geometry_buffer_usage: vk.BufferUsageFlags = .{ .vertex_buffer_bit = true, .index_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true };

    if (backend.device.extensions.raytracing) {
        geometry_buffer_usage.acceleration_structure_storage_bit_khr = true;
    }

    const geometry_buffer = try backend.createBuffer(buffer_size, geometry_buffer_usage);
    backend.device.setDebugName(.buffer, backend.buffers.get(geometry_buffer).?.handle, "unified_geometry_buffer");

    const geometry_slice: ?[]u8 = backend.buffers.get(geometry_buffer).?.allocation.getMappedByteSlice();
    const geometry_buffer_binding: u32 = backend.buffers.get(geometry_buffer).?.storage_binding.?.index;

    const mesh_info_buffer = try backend.createBuffer(@sizeOf(GpuMeshEntry) * MaxMeshCount, .{ .storage_buffer_bit = true, .transfer_dst_bit = true });
    backend.device.setDebugName(.buffer, backend.buffers.get(mesh_info_buffer).?.handle, "mesh_info_buffer");

    return .{
        .allocator = allocator,
        .arena = .init(allocator),

        .backend = backend,
        .registry = registry,
        .geometry_buffer = geometry_buffer,
        .geometry_slice = geometry_slice,
        .geometry_buffer_binding = geometry_buffer_binding,
        .buffer_size = buffer_size,

        .map = .init(allocator),

        .mesh_info_buffer = mesh_info_buffer,
    };
}

pub fn deinit(self: *Self) void {
    self.backend.destroyBuffer(self.mesh_info_buffer);
    self.backend.destroyBuffer(self.geometry_buffer);
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
        .vertices = try self.createBuffer(std.mem.sliceAsBytes(mesh.vertices)),
        .indices = try self.createBuffer(std.mem.sliceAsBytes(mesh.indices)),
        .primitives = try self.createBuffer(std.mem.sliceAsBytes(mesh.primitives)),
        .meshlet = null,
    };

    if (mesh.meshlets.len != 0) {
        entry.meshlet = .{
            .meshlets = try self.createBuffer(std.mem.sliceAsBytes(mesh.meshlets)),
            .meshlet_vertices = try self.createBuffer(std.mem.sliceAsBytes(mesh.meshlet_vertices)),
            .meshlet_triangles = try self.createBuffer(std.mem.sliceAsBytes(mesh.meshlet_triangles)),
        };
    }

    try self.map.put(handle, entry);

    const entry_offset: usize = index * @sizeOf(GpuMeshEntry);
    const entry_bytes: []const u8 = std.mem.asBytes(&entry.getGpuEntry(self.geometry_buffer_binding));

    if (self.backend.getBufferMappedSlice(self.mesh_info_buffer)) |mapped_slice| {
        @memcpy(mapped_slice[entry_offset..(entry_offset + entry_bytes.len)], entry_bytes);
    } else {
        try self.backend.getTransferQueue().writeBuffer(self.mesh_info_buffer, entry_offset, entry_bytes);
    }
}

pub fn canUploadMesh(self: *Self, mesh: *const MeshAsset) bool {
    //Can always upload if memory is mapped
    if (self.geometry_slice != null) {
        return true;
    }

    var gpu_mesh_size: usize = 0;
    gpu_mesh_size += std.mem.sliceAsBytes(mesh.vertices).len;
    gpu_mesh_size += std.mem.sliceAsBytes(mesh.indices).len;
    gpu_mesh_size += std.mem.sliceAsBytes(mesh.primitives).len;

    gpu_mesh_size += std.mem.sliceAsBytes(mesh.meshlets).len;
    gpu_mesh_size += std.mem.sliceAsBytes(mesh.meshlet_vertices).len;
    gpu_mesh_size += std.mem.sliceAsBytes(mesh.meshlet_triangles).len;
    gpu_mesh_size += @sizeOf(GpuMeshEntry);

    const transfer_queue = self.backend.getTransferQueue();
    return transfer_queue.hasSpace(gpu_mesh_size);
}

fn createBuffer(self: *Self, data: []const u8) !SubAllocation {
    const allocation = try self.alloc(data.len);
    errdefer self.free(allocation);

    try self.write(allocation, data);

    return allocation;
}

fn canAlloc(self: *Self, size: usize) bool {
    const BASE_ALIGNMENT: usize = 16;
    const aligned_offset = std.mem.alignForward(usize, self.buffer_offset, BASE_ALIGNMENT);
    return (aligned_offset + size) < self.buffer_size;
}

fn alloc(self: *Self, size: usize) error{OutOfMemory}!SubAllocation {
    const BASE_ALIGNMENT: usize = 16;
    const aligned_offset = std.mem.alignForward(usize, self.buffer_offset, BASE_ALIGNMENT);

    if ((aligned_offset + size) > self.buffer_size) {
        return error.OutOfMemory;
    }

    defer self.buffer_offset = aligned_offset + size;

    return SubAllocation{
        .offset = aligned_offset,
        .len = size,
    };
}

fn free(self: *Self, allocation: SubAllocation) void {
    _ = self; // autofix
    _ = allocation; // autofix
    //NOOP: Currently implmented as a memory arena
}

fn write(self: *Self, allocation: SubAllocation, data: []const u8) !void {
    std.debug.assert(allocation.len == data.len);
    if (self.geometry_slice) |buffer_slice| {
        @memcpy(buffer_slice[allocation.offset..(allocation.offset + data.len)], data);
    } else {
        try self.backend.getTransferQueue().writeBuffer(self.geometry_buffer, allocation.offset, data);
    }
}
