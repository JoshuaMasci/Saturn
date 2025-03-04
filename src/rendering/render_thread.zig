const std = @import("std");
const global = @import("../global.zig");

const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;

const RenderSettings = @import("settings.zig").RenderSettings;

const Platform = @import("../platform.zig");
const Window = Platform.getWindow();
const Renderer = Platform.getRenderer();

const rendering_scene = @import("scene.zig");

pub const RenderThreadData = struct {
    const Self = @This();

    renderer: Renderer,

    //Per Frame Data
    temp_allocator: std.heap.ArenaAllocator,
    scene: ?rendering_scene.RenderScene = null,
    camera_transform: ?Transform = null,
    camera: ?Camera = null,

    pub fn deinit(self: *Self) void {
        self.renderer.deinit();
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
    render_thread_data: *RenderThreadData,
    render_signals: *RenderSignals,

    render_thread: std.Thread,

    should_reload: bool = false,

    pub fn init(allocator: std.mem.Allocator, window: Window) !Self {
        const render_thread_data = try allocator.create(RenderThreadData);
        render_thread_data.* = .{
            .renderer = Renderer.init(allocator, window) catch |err| std.debug.panic("Failed to init renderer: {}", .{err}),
            .temp_allocator = std.heap.ArenaAllocator.init(allocator),
        };

        const render_signals = try allocator.create(RenderSignals);
        render_signals.* = .{};

        var render_thread = try std.Thread.spawn(.{}, renderThreadMain, .{ render_thread_data, render_signals });
        render_thread.setName("RenderThread") catch |err| std.log.err("Failed to set render thread name: {}", .{err});
        return .{
            .allocator = allocator,
            .render_thread_data = render_thread_data,
            .render_signals = render_signals,
            .render_thread = render_thread,
        };
    }

    pub fn deinit(self: *Self) void {
        //Tell the render thread to quit
        self.render_signals.quit_thread.store(true, .monotonic);
        self.render_signals.start_render_semphore.post();
        self.render_thread.join();

        self.render_thread_data.deinit();
        self.allocator.destroy(self.render_thread_data);
        self.allocator.destroy(self.render_signals);
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
        self.render_signals.render_done_semaphore.wait();
        _ = self.render_thread_data.temp_allocator.reset(.retain_capacity);
    }

    pub fn submitFrame(self: *Self) void {
        self.render_signals.start_render_semphore.post();
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

        //TODO: default camera fov should be set by render settings
        const DefaultCamera = Camera.Default;
        if (render_thread_data.scene) |*scene| {
            render_thread_data.renderer.renderScene(
                render_thread_data.temp_allocator.allocator(),
                null,
                scene,
                .{
                    .transform = render_thread_data.camera_transform orelse .{},
                    .camera = render_thread_data.camera orelse DefaultCamera,
                },
            );
        }

        render_signals.render_done_semaphore.post();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }
    }
}
