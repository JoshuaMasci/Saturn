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

pub const MeshEntry = struct {
    sphere_pos_radius: [4]f32,

    vertices: SubAllocation,
    indices: SubAllocation,
    primitives: SubAllocation,

    meshlets: SubAllocation,
    meshlet_vertices: SubAllocation,
    meshlet_triangles: SubAllocation,
};

const Self = @This();

allocator: std.mem.Allocator,
backend: *Backend,
registry: *const AssetRegistry,

geometry_buffer: Backend.BufferHandle,
geometry_slice: ?[]u8,
buffer_size: usize,
buffer_offset: usize = 0,

mesh_map: std.AutoArrayHashMap(AssetRegistry.AssetHandle, MeshEntry),

pub fn init(
    allocator: std.mem.Allocator,
    registry: *const AssetRegistry,
    backend: *Backend,
    buffer_size: usize,
) !Self {
    const geometry_buffer = try backend.createBuffer(buffer_size, .{ .vertex_buffer_bit = true, .index_buffer_bit = true, .storage_buffer_bit = true, .transfer_dst_bit = true, .shader_device_address_bit = true });
    const geometry_slice: ?[]u8 = backend.buffers.get(geometry_buffer).?.allocation.getMappedByteSlice();

    return .{
        .allocator = allocator,
        .backend = backend,
        .registry = registry,
        .geometry_buffer = geometry_buffer,
        .geometry_slice = geometry_slice,

        .buffer_size = buffer_size,

        .mesh_map = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.backend.destroyBuffer(self.geometry_buffer);
    self.mesh_map.deinit();
}

pub fn addMesh(self: *Self, handle: AssetRegistry.AssetHandle) void {
    if (!self.mesh_map.contains(handle)) {
        if (self.registry.loadAsset(MeshAsset, self.allocator, handle)) |mesh| {
            defer mesh.deinit(self.allocator);

            const entry: MeshEntry = .{
                .sphere_pos_radius = mesh.sphere_pos_radius,
                .vertices = self.createBuffer(std.mem.sliceAsBytes(mesh.vertices)) catch return,
                .indices = self.createBuffer(std.mem.sliceAsBytes(mesh.indices)) catch return,
                .primitives = self.createBuffer(std.mem.sliceAsBytes(mesh.primitives)) catch return,
                .meshlets = self.createBuffer(std.mem.sliceAsBytes(mesh.meshlets)) catch return,
                .meshlet_vertices = self.createBuffer(std.mem.sliceAsBytes(mesh.meshlet_vertices)) catch return,
                .meshlet_triangles = self.createBuffer(std.mem.sliceAsBytes(mesh.meshlet_triangles)) catch return,
            };

            self.mesh_map.put(handle, entry) catch |err| {
                std.log.err("Failed to append mesh to list {}", .{err});
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
    if ((self.buffer_offset + size) > self.buffer_size) {
        return error.OutOfMemory;
    }
    defer self.buffer_offset += size;
    return .{
        .offset = self.buffer_offset,
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
        try self.backend.frame_data[self.backend.frame_index].transfer_queue.writeBuffer(self.geometry_buffer, allocation.offset, data);
    }
}
