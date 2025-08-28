const std = @import("std");

const global = @import("../global.zig");
const c = @import("../platform/sdl3.zig").c;
const Platform = @import("../platform/sdl3.zig");
const Window = Platform.Window;
const Vulkan = Platform.Vulkan;
const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;
const ImguiRenderer = @import("imgui_renderer.zig");
const PhysicsRenderer = @import("physics_renderer.zig");
const rendering_scene = @import("scene.zig");
const RenderSettings = @import("settings.zig").RenderSettings;
const SceneRenderer = @import("scene_renderer.zig");
const Device = @import("vulkan/device.zig");
const rg = @import("vulkan/render_graph.zig");

const DrawSceneData = struct {
    scene: rendering_scene.RenderScene,
    camera: Camera,
    camera_transform: Transform,
    debug_physics_draw: bool = false,
};

pub const RenderThreadData = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    window: Window,

    device: *Device,
    scene_renderer: SceneRenderer,
    physics_renderer: PhysicsRenderer,
    imgui_renderer: ImguiRenderer,

    //Per Frame Data
    temp_allocator: std.heap.ArenaAllocator,

    draw_scene: ?DrawSceneData = null,

    pub fn deinit(self: *Self) void {
        _ = self.device.device.proxy.deviceWaitIdle() catch {};
        self.scene_renderer.deinit();
        self.physics_renderer.deinit();
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

    pub fn init(allocator: std.mem.Allocator, window: Window, imgui: @import("zimgui")) !Self {
        const device = try allocator.create(Device);
        errdefer allocator.destroy(device);

        const FRAME_IN_FLIGHT_COUNT = 3;
        const swapchain_format = .b8g8r8a8_unorm;
        const depth_format = .d16_unorm;

        device.* = try .init(allocator, FRAME_IN_FLIGHT_COUNT);
        errdefer device.deinit();

        try device.claimWindow(
            window,
            .{
                .image_count = FRAME_IN_FLIGHT_COUNT,
                .format = swapchain_format,
                .vsync = true,
            },
        );

        const scene_renderer = SceneRenderer.init(
            allocator,
            global.asset_registry,
            device,
            swapchain_format,
            depth_format,
            device.bindless_layout,
        ) catch |err| std.debug.panic("Failed to init scene renderer: {}", .{err});

        const physics_renderer = PhysicsRenderer.init(
            allocator,
            global.asset_registry,
            device,
            swapchain_format,
            depth_format,
            device.bindless_layout,
        ) catch |err| std.debug.panic("Failed to init physics renderer: {}", .{err});

        const imgui_renderer = ImguiRenderer.init(
            allocator,
            global.asset_registry,
            device,
            imgui,
            swapchain_format,
            device.bindless_layout,
        ) catch |err| std.debug.panic("Failed to init imgui renderer: {}", .{err});

        const render_thread_data = try allocator.create(RenderThreadData);
        render_thread_data.* = .{
            .allocator = allocator,
            .window = window,
            .device = device,
            .scene_renderer = scene_renderer,
            .physics_renderer = physics_renderer,
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

        const swapchain_texture = render_graph.acquireSwapchainTexture(render_thread_data.window) catch |err| {
            std.log.err("failed to append swapchain: {}", .{err});
            continue;
        };

        if (render_thread_data.draw_scene) |scene_data| {
            const depth_texture = render_graph.createTransientTexture(.{
                .extent = .{ .relative = swapchain_texture },
                .format = .d16_unorm,
                .usage = .{ .depth_stencil_attachment_bit = true },
            }) catch |err| {
                std.log.err("failed to create transient texture: {}", .{err});
                continue;
            };

            render_thread_data.scene_renderer.createRenderPass(
                temp_allocator,
                swapchain_texture,
                depth_texture,
                &scene_data.scene,
                scene_data.camera,
                scene_data.camera_transform,
                &render_graph,
            ) catch |err| {
                std.log.err("failed to build scene render_pass: {}", .{err});
            };

            if (scene_data.debug_physics_draw) {
                render_thread_data.physics_renderer.createRenderPass(
                    temp_allocator,
                    swapchain_texture,
                    depth_texture,
                    scene_data.camera,
                    scene_data.camera_transform,
                    &render_graph,
                ) catch |err| {
                    std.log.err("failed to build physics render_pass: {}", .{err});
                };
            }
        }

        render_thread_data.imgui_renderer.createRenderPass(temp_allocator, swapchain_texture, &render_graph) catch |err| {
            std.log.err("failed to build imgui render_pass: {}", .{err});
        };

        render_thread_data.device.render(temp_allocator, render_graph) catch |err| std.log.err("Failed to render frame: {}", .{err});

        render_signals.render_done_semaphore.post();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }
    }
}
