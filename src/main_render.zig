// Main File for Rendering Sandbox

const std = @import("std");

const AssetRegistry = @import("asset/registry.zig");
const Imgui = @import("imgui.zig");
const sdl3 = @import("platform/sdl3.zig");
const ImguiRenderer = @import("rendering/imgui_renderer.zig");
const Device = @import("rendering/vulkan/device.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{ .enable_memory_limit = true }){};
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("DebugAllocator has a memory leak!", .{});
    };
    const allocator = debug_allocator.allocator();

    var app: App = try .init(allocator);
    defer app.deinit();

    var last_frame_time_ns = std.time.nanoTimestamp();

    while (app.is_running()) {
        const current_time_ns = std.time.nanoTimestamp();
        const delta_time_ns = current_time_ns - last_frame_time_ns;
        const delta_time_s = @as(f32, @floatFromInt(delta_time_ns)) / std.time.ns_per_s;
        last_frame_time_ns = current_time_ns;

        try app.update(delta_time_s, debug_allocator.total_requested_bytes);
    }
}

const App = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    platform_input: sdl3.Input,
    window: sdl3.Window,
    imgui: Imgui,
    asset_registry: AssetRegistry,

    vulkan_device: *Device,
    imgui_renderer: ImguiRenderer,

    temp_allocator: std.heap.ArenaAllocator,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var asset_registry: AssetRegistry = .init(allocator);
        try asset_registry.addRepository("engine", "zig-out/assets");
        try asset_registry.addRepository("game", "zig-out/game-assets");
        errdefer asset_registry.deinit();

        try sdl3.init(allocator);

        const imgui: Imgui = try .init(allocator);
        errdefer imgui.deinit();

        var platform_input: sdl3.Input = try .init(allocator);
        errdefer platform_input.deinit();

        var window: sdl3.Window = .init("Saturn Render Sandbox", .{ .windowed = .{ 1920, 1080 } });
        errdefer window.deinit();

        const vulkan_device = try allocator.create(Device);
        errdefer allocator.destroy(vulkan_device);

        vulkan_device.* = try .init(allocator, 3);
        errdefer vulkan_device.deinit();

        //TODO: fetch or force swapchain to this
        const swapchain_format = .b8g8r8a8_unorm;

        try vulkan_device.claimWindow(window);

        var imgui_renderer: ImguiRenderer = try .init(
            allocator,
            &asset_registry,
            vulkan_device,
            imgui.context,
            swapchain_format,
            vulkan_device.bindless_layout,
        );
        errdefer imgui_renderer.deinit();

        return .{
            .allocator = allocator,
            .asset_registry = asset_registry,
            .platform_input = platform_input,
            .window = window,
            .imgui = imgui,
            .vulkan_device = vulkan_device,
            .imgui_renderer = imgui_renderer,
            .temp_allocator = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.temp_allocator.deinit();

        self.vulkan_device.waitIdle();

        self.imgui_renderer.deinit();
        self.vulkan_device.releaseWindow(self.window);
        self.vulkan_device.deinit();
        self.allocator.destroy(self.vulkan_device);

        self.imgui.deinit();
        self.window.deinit();
        self.platform_input.deinit();

        sdl3.deinit();

        self.asset_registry.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !self.platform_input.should_quit;
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?usize) !void {
        _ = self.temp_allocator.reset(.retain_capacity);
        const temp_allocator = self.temp_allocator.allocator();

        {
            self.timer += delta_time;
            self.frames += 1;
            if (self.timer > 0.1) {
                const avr_delta_time = self.timer / self.frames;
                self.average_dt = avr_delta_time;
                self.timer = 0.0;
                self.frames = 0;
            }
        }

        try self.platform_input.proccessEvents(.{});
        self.imgui.updateInput(&self.platform_input);

        {
            const window_size = self.window.getSize();
            self.imgui.startFrame(window_size, delta_time);
            defer self.imgui.context.endFrame();

            if (self.imgui.context.begin("Performance", null, .{})) {
                self.imgui.context.textFmt("Delta Time: {d:.3} ms", .{self.average_dt * 1000});
                self.imgui.context.textFmt("FPS: {d:.3}", .{1.0 / self.average_dt});
                if (mem_usage_opt) |mem_usage| {
                    const formatted_string: ?[]const u8 = @import("utils.zig").format_bytes(temp_allocator, mem_usage) catch null;
                    if (formatted_string) |mem_usage_string| {
                        defer temp_allocator.free(mem_usage_string);
                        self.imgui.context.textFmt("Memory Usage: {s}", .{mem_usage_string});
                    }
                }
            }
            self.imgui.context.end();
        }

        var render_graph = Device.RenderGraph.init(temp_allocator);
        defer render_graph.deinit();

        {
            const swapchain_texture = try render_graph.acquireSwapchainTexture(self.window);
            var render_pass = try Device.RenderPass.init(temp_allocator, "Screen Pass");
            try render_pass.addColorAttachment(.{
                .texture = swapchain_texture,
                .clear = .{ .float_32 = @splat(0.25) },
                .store = true,
            });
            try render_graph.render_passes.append(render_pass);

            try self.imgui_renderer.createRenderPass(temp_allocator, swapchain_texture, &render_graph);
        }

        try self.vulkan_device.render(temp_allocator, render_graph);
    }
};
