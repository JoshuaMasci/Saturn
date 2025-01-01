const std = @import("std");
const global = @import("../global.zig");

const Transform = @import("../transform.zig");
const Camera = @import("camera.zig").Camera;

const RenderSettings = @import("settings.zig").RenderSettings;

const Renderer = @import("renderer.zig").Renderer;
const rendering_scene = @import("scene.zig");

pub const RenderState = struct {
    const Self = @This();
    temp_allocator: std.heap.ArenaAllocator,
    scene: ?rendering_scene.RenderScene = null,
    camera_transform: ?Transform = null,
    camera: ?Camera = null,

    pub fn deinit(self: *Self) void {
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
    render_state: *RenderState,
    render_signals: *RenderSignals,

    render_thread: std.Thread,

    pub fn init(allocator: std.mem.Allocator, render_settings: RenderSettings) !Self {
        const render_state = try allocator.create(RenderState);
        render_state.* = .{ .temp_allocator = std.heap.ArenaAllocator.init(allocator) };

        const render_signals = try allocator.create(RenderSignals);
        render_signals.* = .{};

        var render_thread = try std.Thread.spawn(.{}, renderThreadMain, .{ render_settings, render_state, render_signals });
        render_thread.setName("RenderThread") catch |err| std.log.err("Failed to set render thread name: {}", .{err});
        return .{
            .allocator = allocator,
            .render_state = render_state,
            .render_signals = render_signals,
            .render_thread = render_thread,
        };
    }

    pub fn deinit(self: *Self) void {
        //Tell the render thread to quit
        self.render_signals.quit_thread.store(true, .monotonic);
        self.render_signals.start_render_semphore.post();
        self.render_thread.join();

        self.render_state.deinit();
        self.allocator.destroy(self.render_state);
        self.allocator.destroy(self.render_signals);
    }

    pub fn beginFrame(self: *Self) void {
        self.render_signals.render_done_semaphore.wait();
        _ = self.render_state.temp_allocator.reset(.retain_capacity);
    }

    pub fn submitFrame(self: *Self) void {
        self.render_signals.start_render_semphore.post();
    }
};

const OpenglContext = @import("opengl/context.zig").Sdl2Context;

fn renderThreadMain(
    render_settings: RenderSettings,
    render_state: *RenderState,
    render_signals: *RenderSignals,
) void {
    std.log.info("Starting Render Thread", .{});
    defer std.log.info("Exiting Render Thread", .{});

    var context = OpenglContext.init_window(render_settings.window_name, render_settings.size, render_settings.vsync) catch |err| std.debug.panic("Failed to init opengl context: {}", .{err});
    defer context.deinit();

    var renderer = global.global_allocator.create(Renderer) catch |err| std.debug.panic("Failed to allocate renderer: {}", .{err});
    defer global.global_allocator.destroy(renderer);

    renderer.* = Renderer.init(global.global_allocator) catch |err| std.debug.panic("Failed to init renderer: {}", .{err});
    defer renderer.deinit();

    //Prepare for first render call
    render_signals.render_done_semaphore.post();

    while (true) {
        render_signals.start_render_semphore.wait();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }

        renderer.clearFramebuffer();

        //TODO: default camera fov should be set by render settings
        const DefaultCamera = Camera.Default;
        if (render_state.scene) |*scene| {
            renderer.renderScene(
                context.getWindowSize() catch |err| std.debug.panic("Failed to get window size: {}", .{err}),
                scene,
                .{
                    .transform = render_state.camera_transform orelse .{},
                    .camera = render_state.camera orelse DefaultCamera,
                },
            );
        }

        //TODO: render here
        context.swapWindow();

        render_signals.render_done_semaphore.post();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }
    }
}