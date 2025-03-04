const std = @import("std");

const MeshAsset = @import("../../asset/mesh.zig");

const c = @import("../../platform/sdl3.zig").c;

const Self = @This();

device: *c.SDL_GPUDevice,
position_buffer: *c.SDL_GPUBuffer,
attribute_buffer: *c.SDL_GPUBuffer,
index_buffer: ?*c.SDL_GPUBuffer,

vertex_count: u32,
index_count: u32,

pub fn init(device: *c.SDL_GPUDevice, mesh: *const MeshAsset) Self {
    const position = createBufferFromSlice(device, MeshAsset.VertexPositions, mesh.positions, c.SDL_GPU_BUFFERUSAGE_VERTEX);
    const attribute = createBufferFromSlice(device, MeshAsset.VertexAttributes, mesh.attributes, c.SDL_GPU_BUFFERUSAGE_VERTEX);

    var index_buffer: ?*c.SDL_GPUBuffer = null;
    if (mesh.indices.len != 0) {
        index_buffer = createBufferFromSlice(device, u32, mesh.indices, c.SDL_GPU_BUFFERUSAGE_INDEX);
    }

    return .{
        .device = device,

        .position_buffer = position,
        .attribute_buffer = attribute,
        .index_buffer = index_buffer,

        .vertex_count = @intCast(mesh.positions.len),
        .index_count = @intCast(mesh.indices.len),
    };
}

pub fn deinit(self: Self) void {
    c.SDL_ReleaseGPUBuffer(self.device, self.position_buffer);
    c.SDL_ReleaseGPUBuffer(self.device, self.attribute_buffer);
    c.SDL_ReleaseGPUBuffer(self.device, self.index_buffer);
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
