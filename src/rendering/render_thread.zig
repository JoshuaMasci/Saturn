const std = @import("std");

const global = @import("../global.zig");
const c = @import("../platform/sdl3.zig").c;
const Platform = @import("../platform/sdl3.zig");
const Window = Platform.Window;
const Vulkan = Platform.Vulkan;
const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;
const rendering_scene = @import("scene.zig");
const RenderSettings = @import("settings.zig").RenderSettings;
const Device = @import("sdl_gpu/device.zig");
const PhyiscsRenderer = @import("sdl_gpu/physics_renderer.zig");
const SceneRenderer = @import("sdl_gpu/scene_renderer.zig").Renderer;

pub const RenderThreadData = struct {
    const Self = @This();

    device: Device,
    window: Window,
    scene_renderer: SceneRenderer,
    physics_renderer: PhyiscsRenderer,

    //Per Frame Data
    temp_allocator: std.heap.ArenaAllocator,
    scene: ?rendering_scene.RenderScene = null,
    camera_transform: ?Transform = null,
    camera: ?Camera = null,

    pub fn deinit(self: *Self) void {
        self.scene_renderer.deinit();
        self.physics_renderer.deinit();
        self.device.releaseWindow(self.window);
        self.device.deinit();
        self.temp_allocator.deinit();
    }
};

const RenderSignals = struct {
    //TODO: replace with atomic flags?
    render_done_semaphore: std.Thread.Semaphore = .{},
    start_render_semphore: std.Thread.Semaphore = .{},
    quit_thread: std.atomic.Value(bool) = .{ .raw = false },
};

pub const RenderThread = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: *RenderThreadData,
    signals: *RenderSignals,

    thread: std.Thread,

    should_reload: bool = false,

    pub fn init(allocator: std.mem.Allocator, window: Window) !Self {
        {
            const VkInstance = @import("vulkan/instance.zig");
            const Swapchain = @import("vulkan/swapchain.zig");
            const instance = try VkInstance.init(allocator, Vulkan.getProcInstanceFunction().?, Vulkan.getInstanceExtensions(), .{ .name = "Saturn Engine", .version = VkInstance.makeVersion(0, 0, 0, 1) });
            defer instance.deinit();

            const surface = Vulkan.createSurface(instance.instance.handle, window, null).?;
            defer Vulkan.destroySurface(instance.instance.handle, surface, null);

            const device = try instance.createDevice(0);
            defer device.deinit();

            const swapchain = try Swapchain.init(device, surface, null);
            defer swapchain.denit();
        }

        const device = Device.init();
        device.claimWindow(window);

        const color_format = c.SDL_GetGPUSwapchainTextureFormat(device.handle, window.handle);
        const depth_fromat = device.getLargestDepthFormat();

        const render_thread_data = try allocator.create(RenderThreadData);
        render_thread_data.* = .{
            .window = window,
            .device = device,
            .scene_renderer = SceneRenderer.init(allocator, device, .{ .color = color_format, .depth = depth_fromat }) catch |err| std.debug.panic("Failed to init renderer: {}", .{err}),
            .physics_renderer = PhyiscsRenderer.init(allocator, device, color_format, depth_fromat) catch |err| std.debug.panic("Failed to init renderer: {}", .{err}),
            .temp_allocator = std.heap.ArenaAllocator.init(allocator),
        };

        const render_signals = try allocator.create(RenderSignals);
        render_signals.* = .{};

        var render_thread = try std.Thread.spawn(.{}, renderThreadMain, .{ render_thread_data, render_signals });
        render_thread.setName("RenderThread") catch |err| std.log.err("Failed to set render thread name: {}", .{err});
        return .{
            .allocator = allocator,
            .data = render_thread_data,
            .signals = render_signals,
            .thread = render_thread,
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
        self.allocator.destroy(self.data);
        self.allocator.destroy(self.signals);
    }

    pub fn quit(self: *Self) void {
        //Tell the render thread to quit
        self.signals.quit_thread.store(true, .monotonic);
        self.signals.start_render_semphore.post();
        self.thread.join();
    }

    pub fn registerWindow(self: *Self, window: Window) void {
        _ = self; // autofix
        _ = window; // autofix
    }
    pub fn deregisterWindow(self: *Self, window: Window) void {
        _ = self; // autofix
        _ = window; // autofix
    }

    pub fn reload(self: *Self) void {
        self.should_reload = true;
    }

    pub fn beginFrame(self: *Self) void {
        self.signals.render_done_semaphore.wait();
        _ = self.data.temp_allocator.reset(.retain_capacity);
    }

    pub fn submitFrame(self: *Self) void {
        self.signals.start_render_semphore.post();
    }
};

fn renderThreadMain(
    render_thread_data: *RenderThreadData,
    render_signals: *RenderSignals,
) void {
    std.log.info("Starting Render Thread", .{});
    defer std.log.info("Exiting Render Thread", .{});

    //Prepare for first render call
    render_signals.render_done_semaphore.post();

    while (true) {
        render_signals.start_render_semphore.wait();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }

        const command_buffer = render_thread_data.device.startCommandBuffer();

        const swapchain_target = render_thread_data.device.acquireSwapchainTexture(render_thread_data.window, command_buffer).?;

        //TODO: default camera fov should be set by render settings
        const DefaultCamera = Camera.Default;
        if (render_thread_data.scene) |*scene| {
            render_thread_data.scene_renderer.render(
                render_thread_data.temp_allocator.allocator(),
                command_buffer,
                swapchain_target.handle,
                swapchain_target.size,
                scene,
                .{
                    .transform = render_thread_data.camera_transform orelse .{},
                    .camera = render_thread_data.camera orelse DefaultCamera,
                },
            );
        }

        render_thread_data.physics_renderer.renderFrame(
            command_buffer,
            swapchain_target.handle,
            swapchain_target.size,
            .{
                .transform = render_thread_data.camera_transform orelse .{},
                .camera = render_thread_data.camera orelse DefaultCamera,
            },
        );

        const zimgui = @import("zimgui");
        zimgui.render();
        zimgui.backend.prepareDrawData(command_buffer);
        {
            const color_target: c.SDL_GPUColorTargetInfo = .{
                .texture = swapchain_target.handle,
                .load_op = c.SDL_GPU_LOADOP_LOAD,
                .store_op = c.SDL_GPU_STOREOP_STORE,
            };
            const render_pass = c.SDL_BeginGPURenderPass(command_buffer, &color_target, 1, null);
            defer c.SDL_EndGPURenderPass(render_pass);

            zimgui.backend.renderDrawData(command_buffer, render_pass.?, null);
        }

        render_thread_data.device.endCommandBuffer(command_buffer);

        render_signals.render_done_semaphore.post();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }
    }
}
