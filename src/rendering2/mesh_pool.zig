const std = @import("std");

const saturn = @import("../root.zig");
const CpuMesh = @import("../asset/mesh.zig");
const TransferQueue = @import("transfer_queue.zig");

const GpuPool = @import("gpu_pool.zig").GpuPool;

fn GpuBuffer(comptime T: type) type {
    return struct {
        const SubAllocation = struct {
            const Empty: @This() = .{ .offset = 0, .len = 0, .device_address = 0 };

            offset: u64,
            len: u64,
            device_address: u64,
        };

        const This = @This();

        device: saturn.DeviceInterface,
        buffer: saturn.BufferHandle,
        byte_slice: ?[]u8,
        device_address: u64,

        element_count: usize,
        element_offset: usize = 0,

        pub fn init(
            device: saturn.DeviceInterface,
            name: [:0]const u8,
            element_count: usize,
            buffer_usage: saturn.BufferUsage,
        ) !This {
            const buffer = try device.createBuffer(.{
                .name = name,
                .size = element_count * @sizeOf(T),
                .usage = buffer_usage,
                .memory = .gpu_only,
            });

            const buffer_info = device.getBufferInfo(buffer).?;
            const byte_slice: ?[]u8 = buffer_info.mapped_slice;
            const device_address = buffer_info.device_address.?;

            return .{
                .device = device,
                .buffer = buffer,
                .byte_slice = byte_slice,
                .device_address = device_address,
                .element_count = element_count,
            };
        }

        pub fn deinit(self: *This) void {
            self.device.destroyBuffer(self.buffer);
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

        pub fn reset(self: *This) void {
            self.element_offset = 0;
        }
    };
}

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
            .vertices = @intFromFloat(total_f * vertex_weight / @sizeOf(CpuMesh.Vertex)),
            .indices = @intFromFloat(total_f * index_weight / @sizeOf(u32)),
            .primitives = @intFromFloat(total_f * primitive_weight / @sizeOf(CpuMesh.Primitive)),
            .meshlets = @intFromFloat(total_f * meshlet_weight / @sizeOf(CpuMesh.Meshlet)),
            .meshlet_vertices = @intFromFloat(total_f * meshlet_vertex_weight / @sizeOf(u32)),
            .meshlet_triangles = @intFromFloat(total_f * meshlet_triangle_weight / @sizeOf(u8)),
        };
    }

    pub fn getTotalBytes(self: BufferSizes) usize {
        var total: usize = 0;
        total += self.vertices * @sizeOf(CpuMesh.Vertex);
        total += self.indices * @sizeOf(u32);
        total += self.primitives * @sizeOf(CpuMesh.Primitive);
        total += self.meshlets * @sizeOf(CpuMesh.Meshlet);
        total += self.meshlet_vertices * @sizeOf(u32);
        total += self.meshlet_triangles * @sizeOf(u8);
        return total;
    }
};

pub const MeshHandle = u32;

pub const MeshInfo = struct {
    const Gpu = extern struct {
        sphere_pos_radius: [4]f32 = @splat(0.0),

        vertex_buffer_offset: u32 = 0,
        index_buffer_offset: u32 = 0,
        primitive_buffer_address: u64 = 0,
        meshlet_buffer_address: u64 = 0,

        meshlet_vertex_buffer_address: u64 = 0,
        meshlet_triangle_buffer_address: u64 = 0,
        meshlets_loaded: u32 = 0,
        loaded: u32 = 0,
    };

    cpu_primitives: []const CpuMesh.Primitive,

    sphere_pos_radius: [4]f32,

    vertices: GpuBuffer(CpuMesh.Vertex).SubAllocation,
    indices: GpuBuffer(u32).SubAllocation,
    primitives: GpuBuffer(CpuMesh.Primitive).SubAllocation,

    fn getGpu(self: MeshInfo) Gpu {
        return .{
            .sphere_pos_radius = self.sphere_pos_radius,
            .vertex_buffer_offset = @intCast(self.vertices.offset),
            .index_buffer_offset = @intCast(self.indices.offset),
            .primitive_buffer_address = self.primitives.device_address,
            .loaded = 1,
        };
    }
};

const Self = @This();

gpa: std.mem.Allocator,
device: saturn.DeviceInterface,

info_buffer: GpuPool(MeshInfo.Gpu),

map: std.AutoHashMapUnmanaged(MeshHandle, MeshInfo) = .empty,

//TODO: move back to monolithic buffer, once legacy vertex pipeline is not needed
vertex_buffer: GpuBuffer(CpuMesh.Vertex),
index_buffer: GpuBuffer(u32),
primitive_buffer: GpuBuffer(CpuMesh.Primitive),

pub fn init(
    gpa: std.mem.Allocator,
    device: saturn.DeviceInterface,
    buffer_sizes: BufferSizes,
    max_mesh_count: usize,
) !Self {
    const geometry_buffer_usage: saturn.BufferUsage = .{
        .vertex = true,
        .index = true,
        .transfer_dst = true,
        .device_address = true,
    };

    var vertex_buffer = try GpuBuffer(CpuMesh.Vertex).init(device, "vertex_buffer", buffer_sizes.vertices, geometry_buffer_usage);
    errdefer vertex_buffer.deinit();

    var index_buffer = try GpuBuffer(u32).init(device, "index_buffer", buffer_sizes.indices, geometry_buffer_usage);
    errdefer index_buffer.deinit();

    var primitive_buffer = try GpuBuffer(CpuMesh.Primitive).init(device, "primitive_buffer", buffer_sizes.primitives, geometry_buffer_usage);
    errdefer primitive_buffer.deinit();

    var info_buffer: GpuPool(MeshInfo.Gpu) = try .init(gpa, device, "mesh_info_buffer", max_mesh_count, .{ .storage = true, .transfer_dst = true, .device_address = true }, .{});
    errdefer info_buffer.deinit();

    return .{
        .gpa = gpa,
        .device = device,

        .info_buffer = info_buffer,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .primitive_buffer = primitive_buffer,
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.map.valueIterator();
    while (iter.next()) |info| {
        self.gpa.free(info.cpu_primitives);
    }
    self.map.deinit(self.gpa);
    self.info_buffer.deinit();
    self.vertex_buffer.deinit();
    self.index_buffer.deinit();
    self.primitive_buffer.deinit();
}

pub fn create(self: *Self) error{OutOfMemory}!MeshHandle {
    return try self.info_buffer.alloc();
}

pub fn destroy(self: *Self, handle: MeshHandle) void {
    self.unload(handle);
    self.info_buffer.free(handle);
}

pub fn load(self: *Self, transfer_queue: *TransferQueue, handle: MeshHandle, mesh: *const CpuMesh) saturn.Error!void {
    std.debug.assert(!self.map.contains(handle));

    const cpu_primitives = try self.gpa.dupe(CpuMesh.Primitive, mesh.primitives);
    errdefer self.gpa.free(cpu_primitives);

    const vertices = try self.vertex_buffer.alloc(mesh.vertices.len);
    errdefer self.vertex_buffer.free(vertices);

    const indices = try self.index_buffer.alloc(mesh.indices.len);
    errdefer self.index_buffer.free(indices);

    const primitives = try self.primitive_buffer.alloc(mesh.primitives.len);
    errdefer self.vertex_buffer.free(primitives);

    const info: MeshInfo = .{
        .cpu_primitives = cpu_primitives,
        .sphere_pos_radius = mesh.sphere_pos_radius,
        .vertices = vertices,
        .indices = indices,
        .primitives = primitives,
    };
    errdefer self.info_buffer.stage(handle, .{});

    try transfer_queue.addBulkBufferUpload(&.{
        .{ .dst = self.vertex_buffer.buffer, .offset = info.vertices.offset * @sizeOf(CpuMesh.Vertex), .data = std.mem.sliceAsBytes(mesh.vertices) },
        .{ .dst = self.index_buffer.buffer, .offset = info.indices.offset * @sizeOf(u32), .data = std.mem.sliceAsBytes(mesh.indices) },
        .{ .dst = self.primitive_buffer.buffer, .offset = info.primitives.offset * @sizeOf(CpuMesh.Primitive), .data = std.mem.sliceAsBytes(mesh.primitives) },
    });

    try self.map.put(self.gpa, handle, info);
    self.info_buffer.stage(handle, info.getGpu());
}

pub fn unload(self: *Self, handle: MeshHandle) void {
    if (self.map.fetchRemove(handle)) |entry| {
        self.gpa.free(entry.value.cpu_primitives);
        self.vertex_buffer.free(entry.value.vertices);
        self.index_buffer.free(entry.value.indices);
        self.primitive_buffer.free(entry.value.primitives);
        self.info_buffer.stage(handle, .{});
    }
}
