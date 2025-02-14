const std = @import("std");
const za = @import("zalgebra");
const global = @import("../../global.zig");

const Transform = @import("../../transform.zig");
const Camera = @import("../camera.zig").Camera;
const RenderScene = @import("../scene.zig").RenderScene;

const Settings = @import("../../rendering/settings.zig");

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
});

pub const WindowHandle = *anyopaque;

pub const Renderer = struct {
    const Self = @This();

    gpu_device: *c.SDL_GPUDevice,

    window: ?*c.SDL_Window = null,

    pub fn init(allocator: std.mem.Allocator, settings: Settings.RenderSettings) !Self {
        std.debug.assert(c.SDL_Init(c.SDL_INIT_VIDEO));
        const gpu_device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV, true, null).?;

        _ = allocator; // autofix

        var self: Self =
            .{
            .gpu_device = gpu_device,
        };

        self.window = @ptrCast(self.createWindow(settings.window_name, settings.size, settings.vsync));

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.window) |window| {
            self.destroyWindow(@ptrCast(window));
        }

        c.SDL_DestroyGPUDevice(self.gpu_device);
    }

    pub fn clearFramebuffer(self: *Self) void {
        _ = self; // autofix

    }

    pub fn createWindow(self: *Self, name: [:0]const u8, size: Settings.WindowSize, vsync: Settings.VerticalSync) WindowHandle {
        var window_width: i32 = 0;
        var window_height: i32 = 0;
        var window_flags = c.SDL_WINDOW_RESIZABLE;

        switch (size) {
            .windowed => |window_size| {
                window_width = window_size[0];
                window_height = window_size[1];
            },
            .maximized => window_flags |= c.SDL_WINDOW_MAXIMIZED,
            .fullscreen => window_flags |= c.SDL_WINDOW_FULLSCREEN,
        }

        const window = c.SDL_CreateWindow(name, window_width, window_height, window_flags).?;
        std.debug.assert(c.SDL_ClaimWindowForGPUDevice(self.gpu_device, window));

        const present_mode: c.SDL_GPUPresentMode = switch (vsync) {
            .on => c.SDL_GPU_PRESENTMODE_VSYNC,
            .off => c.SDL_GPU_PRESENTMODE_IMMEDIATE,
        };
        std.debug.assert(c.SDL_SetGPUSwapchainParameters(self.gpu_device, window, c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, present_mode));

        return @ptrCast(window);
    }
    pub fn destroyWindow(self: *Self, handle: WindowHandle) void {
        const window: *c.SDL_Window = @ptrCast(handle);
        c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, window);
        c.SDL_DestroyWindow(window);
    }

    pub fn renderScene(self: *Self, target: ?WindowHandle, scene: *const RenderScene, camera: struct {
        transform: Transform,
        camera: Camera,
    }) void {
        _ = target; // autofix
        _ = scene; // autofix
        _ = camera; // autofix
        const window: *c.SDL_Window = @ptrCast(self.window);

        const command_buffer = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
        defer _ = c.SDL_SubmitGPUCommandBuffer(command_buffer);

        var swapchain_texture: ?*c.SDL_GPUTexture = null;
        _ = c.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, null, null);

        const color_target: c.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_texture,
            .clear_color = .{ .r = 0.0, .g = 0.75, .b = 0.5, .a = 1.0 },
            .load_op = c.SDL_GPU_LOADOP_CLEAR,
            .store_op = c.SDL_GPU_STOREOP_STORE,
        };
        const render_pass = c.SDL_BeginGPURenderPass(command_buffer, &color_target, 1, null);
        defer c.SDL_EndGPURenderPass(render_pass);
    }
};
