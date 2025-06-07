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
const Device = @import("vulkan/device.zig");
const SceneRenderer = @import("scene_renderer.zig");
const ImguiRenderer = @import("imgui_renderer.zig");
const rg = @import("vulkan/render_graph.zig");

pub const RenderThreadData = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    window: Window,

    device: *Device,
    scene_renderer: SceneRenderer,
    imgui_renderer: ImguiRenderer,

    //Per Frame Data
    temp_allocator: std.heap.ArenaAllocator,
    scene: ?rendering_scene.RenderScene = null,
    camera_transform: ?Transform = null,
    camera: ?Camera = null,

    pub fn deinit(self: *Self) void {
        _ = self.device.device.proxy.deviceWaitIdle() catch {};
        self.scene_renderer.deinit();
        self.imgui_renderer.deinit();

        self.device.releaseWindow(self.window);
        self.device.deinit();
        self.allocator.destroy(self.device);
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
        const device = try allocator.create(Device);
        errdefer allocator.destroy(device);

        device.* = try .init(allocator, 3);
        errdefer device.deinit();

        try device.claimWindow(window);

        const scene_renderer = SceneRenderer.init(
            allocator,
            device,
            .b8g8r8a8_unorm,
            .d32_sfloat,
            device.bindless_layout,
        ) catch |err| std.debug.panic("Failed to init renderer: {}", .{err});

        const imgui_renderer = ImguiRenderer.init(
            allocator,
            device,
            .b8g8r8a8_unorm,
            device.bindless_layout,
        ) catch |err| std.debug.panic("Failed to init renderer: {}", .{err});

        const render_thread_data = try allocator.create(RenderThreadData);
        render_thread_data.* = .{
            .allocator = allocator,
            .window = window,
            .device = device,
            .scene_renderer = scene_renderer,
            .imgui_renderer = imgui_renderer,
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
    const temp_allocator = render_thread_data.temp_allocator.allocator();

    std.log.info("Starting Render Thread", .{});
    defer std.log.info("Exiting Render Thread", .{});

    //Prepare for first render call
    render_signals.render_done_semaphore.post();

    while (true) {
        render_signals.start_render_semphore.wait();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }

        var render_graph = rg.RenderGraph.init(temp_allocator);
        defer render_graph.deinit();

        var scene_build_fn: ?rg.CommandBufferBuildFn = null;
        var scene_build_data: SceneRenderer.BuildCommandBufferData = undefined;

        if (render_thread_data.scene) |*scene| {
            render_thread_data.scene_renderer.loadSceneData(temp_allocator, scene);
            scene_build_fn = SceneRenderer.buildCommandBuffer;
            scene_build_data = .{
                .self = &render_thread_data.scene_renderer,
                .camera = render_thread_data.camera orelse .Default,
                .camera_transform = render_thread_data.camera_transform orelse .{},
                .scene = scene,
            };
        }

        const swapchain_texture = render_graph.acquireSwapchainTexture(render_thread_data.window) catch |err| {
            std.log.err("failed to append swapchain: {}", .{err});
            continue;
        };

        const depth_texture = render_graph.createTransientTexture(.{
            .extent = .{ .relative = swapchain_texture },
            .format = .d32_sfloat,
            .usage = .{ .depth_stencil_attachment_bit = true },
        }) catch |err| {
            std.log.err("failed to create transient texture: {}", .{err});
            continue;
        };

        var render_pass = rg.RenderPass.init(temp_allocator, "Scene Pass") catch |err| {
            std.log.err("failed to create render pass: {}", .{err});
            continue;
        };
        render_pass.addColorAttachment(.{
            .texture = swapchain_texture,
            .clear = .{ .float_32 = .{ 0.576, 0.439, 0.859, 1.0 } },
            .store = true,
        }) catch |err| {
            std.log.err("failed to create color attachment: {}", .{err});
            continue;
        };
        render_pass.addDepthAttachment(.{
            .texture = depth_texture,
            .clear = 1.0,
            .store = true,
        });
        if (scene_build_fn) |build_fn| {
            render_pass.addBuildFn(build_fn, &scene_build_data);
        }

        render_graph.render_passes.append(render_pass) catch |err| {
            std.log.err("failed to append render_pass: {}", .{err});
            continue;
        };

        render_thread_data.imgui_renderer.createRenderPass(temp_allocator, swapchain_texture, &render_graph) catch |err| {
            std.log.err("failed to build imgui render_pass: {}", .{err});
            continue;
        };

        render_thread_data.device.render(temp_allocator, render_graph) catch |err| std.log.err("Failed to render frame: {}", .{err});

        render_signals.render_done_semaphore.post();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }
    }
}
