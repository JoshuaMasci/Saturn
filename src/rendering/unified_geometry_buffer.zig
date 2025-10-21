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
        //const meshlet = self.meshlet orelse .{};

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
    const geometry_buffer = try backend.createBuffer(buffer_size, .{ .vertex_buffer_bit = true, .index_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true });
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

pub fn addMesh(self: *Self, handle: AssetRegistry.AssetHandle) void {
    if (!self.map.contains(handle)) {
        if (self.registry.loadAsset(MeshAsset, self.allocator, handle)) |mesh| {
            defer mesh.deinit(self.allocator);

            const index = self.next_mesh_index;
            self.next_mesh_index += 1;

            const entry: MeshEntry = .{
                .cpu_primitives = self.arena.allocator().dupe(MeshAsset.Primitive, mesh.primitives) catch return,
                .index = index,
                .sphere_pos_radius = mesh.sphere_pos_radius,
                .vertices = self.createBuffer(std.mem.sliceAsBytes(mesh.vertices)) catch return,
                .indices = self.createBuffer(std.mem.sliceAsBytes(mesh.indices)) catch return,
                .primitives = self.createBuffer(std.mem.sliceAsBytes(mesh.primitives)) catch return,
                .meshlet = .{
                    .meshlets = self.createBuffer(std.mem.sliceAsBytes(mesh.meshlets)) catch return,
                    .meshlet_vertices = self.createBuffer(std.mem.sliceAsBytes(mesh.meshlet_vertices)) catch return,
                    .meshlet_triangles = self.createBuffer(std.mem.sliceAsBytes(mesh.meshlet_triangles)) catch return,
                },
            };

            self.map.put(handle, entry) catch |err| {
                std.log.err("Failed to append mesh to list {}", .{err});
            };

            const offset: usize = index * @sizeOf(GpuMeshEntry);
            self.backend.writeBuffer(self.mesh_info_buffer, offset, std.mem.asBytes(&entry.getGpuEntry(self.geometry_buffer_binding))) catch |err| {
                std.log.err("Failed to upload mesh info to buffer {}", .{err});
            };
        } else |err| {
            std.log.err("Failed to load mesh {}", .{err});
        }
    }
}

fn createBuffer(self: *Self, data: []const u8) !SubAllocation {
    const allocation = try self.alloc(data.len);
    errdefer self.free(allocation);

    try self.write(allocation, data);

    return allocation;
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
        try self.backend.writeBuffer(self.geometry_buffer, allocation.offset, data);
    }
}
