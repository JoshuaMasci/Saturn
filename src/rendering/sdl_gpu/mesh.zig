const std = @import("std");

const MeshAsset = @import("../../asset/mesh.zig");

const c = @import("../../platform/sdl3.zig").c;

pub const Primitive = struct {
    vertex_buffer: *c.SDL_GPUBuffer,
    index_buffer: ?*c.SDL_GPUBuffer,

    vertex_count: u32,
    index_count: u32,
};

const Self = @This();

allocator: std.mem.Allocator,
device: *c.SDL_GPUDevice,
primitives: []Primitive,

pub fn init(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, mesh: *const MeshAsset) !Self {
    var primitives = try allocator.alloc(Primitive, mesh.primitives.len);
    for (mesh.primitives, 0..) |primitive, i| {
        const vertex_buffer = createBufferFromSlice(device, MeshAsset.Vertex, primitive.vertices, c.SDL_GPU_BUFFERUSAGE_VERTEX);

        var index_buffer: ?*c.SDL_GPUBuffer = null;
        if (mesh.primitives[0].indices.len != 0) {
            index_buffer = createBufferFromSlice(device, u32, primitive.indices, c.SDL_GPU_BUFFERUSAGE_INDEX);
        }

        primitives[i] = .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .vertex_count = @intCast(primitive.vertices.len),
            .index_count = @intCast(primitive.indices.len),
        };
    }

    return .{
        .allocator = allocator,
        .device = device,
        .primitives = primitives,
    };
}

pub fn deinit(self: Self) void {
    for (self.primitives) |primitive| {
        c.SDL_ReleaseGPUBuffer(self.device, primitive.vertex_buffer);
        c.SDL_ReleaseGPUBuffer(self.device, primitive.index_buffer);
    }
    self.allocator.free(self.primitives);
}

//TODO: don't upload during creation
fn createBufferFromSlice(device: *c.SDL_GPUDevice, comptime T: type, slice: []const T, usage: c.SDL_GPUBufferUsageFlags) *c.SDL_GPUBuffer {
    const buffer_size: u32 = @intCast(slice.len * @sizeOf(T));
    const buffer = c.SDL_CreateGPUBuffer(device, &.{
        .usage = usage,
        .size = buffer_size,
    }).?;
    const upload_buffer = c.SDL_CreateGPUTransferBuffer(device, &.{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = buffer_size,
    }).?;
    defer c.SDL_ReleaseGPUTransferBuffer(device, upload_buffer);

    const mapped_ptr: [*]T = @alignCast(@ptrCast(c.SDL_MapGPUTransferBuffer(device, upload_buffer, false)));
    const mapped_slice: []T = mapped_ptr[0..slice.len];
    @memcpy(mapped_slice, slice);
    c.SDL_UnmapGPUTransferBuffer(device, upload_buffer);

    const command_buffer = c.SDL_AcquireGPUCommandBuffer(device);
    defer _ = c.SDL_SubmitGPUCommandBuffer(command_buffer);

    const copy_pass = c.SDL_BeginGPUCopyPass(command_buffer);
    defer c.SDL_EndGPUCopyPass(copy_pass);

    c.SDL_UploadToGPUBuffer(copy_pass, &.{
        .offset = 0,
        .transfer_buffer = upload_buffer,
    }, &.{
        .buffer = buffer,
        .offset = 0,
        .size = buffer_size,
    }, false);

    return buffer;
}
