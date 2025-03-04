const std = @import("std");

const Texture2dAsset = @import("../../asset/texture_2d.zig");

const c = @import("../../platform/sdl3.zig").c;

const Self = @This();

device: *c.SDL_GPUDevice,

handle: *c.SDL_GPUTexture,

pub fn init_2d(device: *c.SDL_GPUDevice, texture_asset: *const Texture2dAsset) Self {
    const format: c.SDL_GPUTextureFormat = switch (texture_asset.format) {
        .r8 => c.SDL_GPU_TEXTUREFORMAT_R8_UNORM,
        .rg8 => c.SDL_GPU_TEXTUREFORMAT_R8G8_UNORM,
        .rgba8 => c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    };

    const handle = c.SDL_CreateGPUTexture(device, &.{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = format,
        .width = texture_asset.width,
        .height = texture_asset.height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
    }).?;
    uploadToTexture(device, handle, .{ texture_asset.width, texture_asset.height }, texture_asset.data);

    return .{
        .device = device,
        .handle = handle,
    };
}

pub fn deinit(self: Self) void {
    c.SDL_ReleaseGPUTexture(self.device, self.handle);
}

//TODO: don't upload during creation
fn uploadToTexture(device: *c.SDL_GPUDevice, texture: *c.SDL_GPUTexture, texture_size: [2]u32, bytes: []const u8) void {
    const upload_buffer = c.SDL_CreateGPUTransferBuffer(device, &.{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(bytes.len),
    }).?;
    defer c.SDL_ReleaseGPUTransferBuffer(device, upload_buffer);

    const mapped_ptr: [*]u8 = @alignCast(@ptrCast(c.SDL_MapGPUTransferBuffer(device, upload_buffer, false)));
    const mapped_slice: []u8 = mapped_ptr[0..bytes.len];
    @memcpy(mapped_slice, bytes);
    c.SDL_UnmapGPUTransferBuffer(device, upload_buffer);

    const command_buffer = c.SDL_AcquireGPUCommandBuffer(device);
    defer _ = c.SDL_SubmitGPUCommandBuffer(command_buffer);

    const copy_pass = c.SDL_BeginGPUCopyPass(command_buffer);
    defer c.SDL_EndGPUCopyPass(copy_pass);

    c.SDL_UploadToGPUTexture(copy_pass, &.{
        .offset = 0,
        .transfer_buffer = upload_buffer,
    }, &.{
        .texture = texture,
        .x = 0,
        .y = 0,
        .z = 0,
        .w = texture_size[0],
        .h = texture_size[1],
        .d = 1,
        .mip_level = 0,
        .layer = 0,
    }, false);
}
