const std = @import("std");

const sdl3 = @import("../../platform/sdl3.zig");
const c = sdl3.c;
const Window = sdl3.Window;

const Self = @This();

handle: *c.SDL_GPUDevice,
shader_format: c.SDL_GPUShaderFormat,

pub fn init() Self {
    std.debug.assert(c.SDL_Init(c.SDL_INIT_VIDEO));
    const handle = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, null).?;

    const driver_name: [*c]const u8 = c.SDL_GetGPUDeviceDriver(handle);
    const shader_format = c.SDL_GetGPUShaderFormats(handle);

    std.log.info("SDL_GPU Context:\n\tBackend: {s}\n\tShader: {}", .{
        driver_name,
        shader_format,
    });

    return .{
        .handle = handle,
        .shader_format = shader_format,
    };
}

pub fn deinit(self: *Self) void {
    c.SDL_DestroyGPUDevice(self.handle);
}

pub fn claimWindow(self: Self, window: Window) void {
    _ = c.SDL_ClaimWindowForGPUDevice(self.handle, window.handle);
}
pub fn releaseWindow(self: Self, window: Window) void {
    _ = c.SDL_ReleaseWindowFromGPUDevice(self.handle, window.handle);
}

pub fn startCommandBuffer(self: Self) *c.SDL_GPUCommandBuffer {
    return c.SDL_AcquireGPUCommandBuffer(self.handle).?;
}

pub fn endCommandBuffer(self: Self, command_buffer: *c.SDL_GPUCommandBuffer) void {
    _ = self; // autofix
    _ = c.SDL_SubmitGPUCommandBuffer(command_buffer);
}

pub fn acquireSwapchainTexture(self: Self, window: Window, command_buffer: *c.SDL_GPUCommandBuffer) ?struct { handle: ?*c.SDL_GPUTexture, size: [2]u32 } {
    _ = self; // autofix
    var handle: ?*c.SDL_GPUTexture = null;
    var size: [2]u32 = undefined;
    if (c.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, window.handle, &handle, &size[0], &size[1])) {
        return .{ .handle = handle, .size = size };
    }
    return null;
}

pub fn getLargestDepthFormat(self: Self) c.SDL_GPUTextureFormat {
    var depth_format: c.SDL_GPUTextureFormat = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM;
    if (c.SDL_GPUTextureSupportsFormat(self.handle, c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT, c.SDL_GPU_TEXTURETYPE_2D, c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) {
        depth_format = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
    } else if (c.SDL_GPUTextureSupportsFormat(self.handle, c.SDL_GPU_TEXTUREFORMAT_D24_UNORM, c.SDL_GPU_TEXTURETYPE_2D, c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) {
        depth_format = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM;
    }
    return depth_format;
}
