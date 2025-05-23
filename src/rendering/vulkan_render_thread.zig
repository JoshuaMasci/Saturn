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

//Vulkan
const Device = @import("vulkan/backend.zig");
const SceneRenderer = @import("vulkan/scene_renderer.zig");
// const PhyiscsRenderer = @import("sdl_gpu/physics_renderer.zig");

pub const RenderThreadData = struct {
    const Self = @This();

    window: Window,

    device: Device,
    scene_renderer: SceneRenderer,

    //Per Frame Data
    temp_allocator: std.heap.ArenaAllocator,
    scene: ?rendering_scene.RenderScene = null,
    camera_transform: ?Transform = null,
    camera: ?Camera = null,

    pub fn deinit(self: *Self) void {
        self.scene_renderer.deinit();
        // self.physics_renderer.deinit();
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
        var device = try Device.init(allocator);
        try device.claimWindow(window);

        // const color_format = c.SDL_GetGPUSwapchainTextureFormat(device.handle, window.handle);
        // _ = color_format; // autofix
        // const depth_fromat = device.getLargestDepthFormat();
        // _ = depth_fromat; // autofix

        const scene_renderer = SceneRenderer.init(allocator, device.device) catch |err| std.debug.panic("Failed to init renderer: {}", .{err});

        const render_thread_data = try allocator.create(RenderThreadData);
        render_thread_data.* = .{
            .window = window,
            .device = device,
            .scene_renderer = scene_renderer,
            // .physics_renderer = PhyiscsRenderer.init(allocator, device, color_format, depth_fromat) catch |err| std.debug.panic("Failed to init renderer: {}", .{err}),
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

        if (render_thread_data.scene) |scene| {
            render_thread_data.scene_renderer.loadSceneData(render_thread_data.temp_allocator.allocator(), &scene);
            render_thread_data.device.render(render_thread_data.window, null, null) catch |err| std.log.err("Failed to render frame: {}", .{err});
        } else {
            render_thread_data.device.render(render_thread_data.window, null, null) catch |err| std.log.err("Failed to render frame: {}", .{err});
        }

        render_signals.render_done_semaphore.post();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }
    }
}
