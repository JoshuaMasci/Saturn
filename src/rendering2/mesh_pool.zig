const std = @import("std");

const saturn = @import("../root.zig");
const AssetRegistry = @import("../asset/registry.zig");
const CpuMesh = @import("../asset/mesh.zig");

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

        pub fn write(self: *This, allocation: SubAllocation, data: []const T) !void {
            std.debug.assert(allocation.len == data.len);
            const byte_offset = allocation.offset * @sizeOf(T);
            const data_bytes = std.mem.sliceAsBytes(data);

            if (self.byte_slice) |slice| {
                @memcpy(slice[byte_offset..(byte_offset + data_bytes.len)], data_bytes);
            } else {
                std.debug.panic("Transfer Queue Not implmented yet", .{});
                //try self.backend.getTransferQueue().writeBuffer(self.buffer, byte_offset, data_bytes);
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

        pub fn reset(self: *This) void {
            self.element_offset = 0;
        }
    };
}

pub const MeshEntry = struct {
    const Gpu = extern struct {
        sphere_pos_radius: [4]f32,

        vertex_buffer_offset: u32,
        index_buffer_offset: u32,
        primitive_buffer_address: u64,
        meshlet_buffer_address: u64,

        meshlet_vertex_buffer_address: u64,
        meshlet_triangle_buffer_address: u64,
        meshlets_loaded: u32,
        _padding: u32 = 0,
    };

    sphere_pos_radius: [4]f32,

    vertices: GpuBuffer(CpuMesh.Vertex).SubAllocation,
    indices: GpuBuffer(u32).SubAllocation,
    primitives: GpuBuffer(CpuMesh.Primitive).SubAllocation,

    meshlet: ?struct {
        meshlets: GpuBuffer(CpuMesh.Meshlet).SubAllocation,
        meshlet_vertices: GpuBuffer(u32).SubAllocation,
        meshlet_triangles: GpuBuffer(u8).SubAllocation,
    } = null,

    fn getGpuEntry(self: MeshEntry) Gpu {
        return .{
            .sphere_pos_radius = self.sphere_pos_radius,
            .vertex_buffer_offset = @intCast(self.vertices.offset),
            .index_buffer_offset = @intCast(self.indices.offset),
            .primitive_buffer_address = self.primitives.device_address,
            .meshlet_buffer_address = if (self.meshlet) |meshlet| meshlet.meshlets.device_address else 0,
            .meshlet_vertex_buffer_address = if (self.meshlet) |meshlet| meshlet.meshlet_vertices.device_address else 0,
            .meshlet_triangle_buffer_address = if (self.meshlet) |meshlet| meshlet.meshlet_triangles.device_address else 0,
            .meshlets_loaded = @intFromBool(self.meshlet != null),
        };
    }
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

const Self = @This();

device: saturn.DeviceInterface,

vertex_buffer: GpuBuffer(CpuMesh.Vertex),
index_buffer: GpuBuffer(u32),
primitive_buffer: GpuBuffer(CpuMesh.Primitive),
meshlet_buffer: GpuBuffer(CpuMesh.Meshlet),
meshlet_vertex_buffer: GpuBuffer(u32),
meshlet_triangle_buffer: GpuBuffer(u8),

pub fn init(
    device: saturn.DeviceInterface,
    buffer_sizes: BufferSizes,
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

    var meshlet_buffer = try GpuBuffer(CpuMesh.Meshlet).init(device, "meshlet_buffer", buffer_sizes.meshlets, geometry_buffer_usage);
    errdefer meshlet_buffer.deinit();

    var meshlet_vertex_buffer = try GpuBuffer(u32).init(device, "meshlet_vertex_buffer", buffer_sizes.meshlet_vertices, geometry_buffer_usage);
    errdefer meshlet_vertex_buffer.deinit();

    var meshlet_triangle_buffer = try GpuBuffer(u8).init(device, "meshlet_triangle_buffer", buffer_sizes.meshlet_triangles, geometry_buffer_usage);
    errdefer meshlet_triangle_buffer.deinit();

    return .{
        .device = device,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .primitive_buffer = primitive_buffer,
        .meshlet_buffer = meshlet_buffer,
        .meshlet_vertex_buffer = meshlet_vertex_buffer,
        .meshlet_triangle_buffer = meshlet_triangle_buffer,
    };
}

pub fn deinit(self: *Self) void {
    self.vertex_buffer.deinit();
    self.index_buffer.deinit();
    self.primitive_buffer.deinit();
    self.meshlet_buffer.deinit();
    self.meshlet_vertex_buffer.deinit();
    self.meshlet_triangle_buffer.deinit();
}

pub fn addMesh(self: *Self, mesh: *const CpuMesh) !MeshEntry {
    if (self.vertex_buffer.byte_slice == null) {
        return error.CantUploadMesh;
    }

    const entry: MeshEntry = .{
        .sphere_pos_radius = mesh.sphere_pos_radius,
        .vertices = try self.vertex_buffer.alloc(mesh.vertices.len),
        .indices = try self.index_buffer.alloc(mesh.indices.len),
        .primitives = try self.primitive_buffer.alloc(mesh.primitives.len),
        .meshlet = null,
    };

    // if (mesh.meshlets.len != 0) {
    //     entry.meshlet = .{
    //         .meshlets = try self.meshlet_buffer.alloc(mesh.meshlets.len),
    //         .meshlet_vertices = try self.meshlet_vertex_buffer.alloc(mesh.meshlet_vertices.len),
    //         .meshlet_triangles = try self.meshlet_triangle_buffer.alloc(mesh.meshlet_triangles.len),
    //     };
    // }

    return entry;
}

pub fn canWriteMesh(self: *const Self) bool {
    return (self.vertex_buffer.byte_slice != null) and
        (self.index_buffer.byte_slice != null) and
        (self.primitive_buffer.byte_slice != null) and
        (self.meshlet_buffer.byte_slice != null) and
        (self.meshlet_vertex_buffer.byte_slice != null) and
        (self.meshlet_triangle_buffer.byte_slice != null);
}
