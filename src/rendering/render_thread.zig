const std = @import("std");
const global = @import("../global.zig");

const Transform = @import("../transform.zig");
const Camera = @import("../camera.zig").Camera;

const RenderSettings = @import("settings.zig").RenderSettings;

const rendering = @import("../rendering.zig");

pub const RenderState = struct {
    const Self = @This();
    temp_allocator: std.heap.ArenaAllocator,
    scene: ?*const rendering.Scene = null,
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
    }

    pub fn submitFrame(self: *Self) void {
        self.render_signals.start_render_semphore.post();
    }
};

const OpenglContext = @import("../platform/opengl/context.zig").Sdl2Context;

fn renderThreadMain(
    render_settings: RenderSettings,
    render_state: *RenderState,
    render_signals: *RenderSignals,
) void {
    std.log.info("Starting Render Thread", .{});
    defer std.log.info("Exiting Render Thread", .{});

    var context = OpenglContext.init_window(render_settings.window_name, render_settings.size, render_settings.vsync) catch |err| std.debug.panic("Failed to init opengl context: {}", .{err});
    defer context.deinit();

    var renderer = global.global_allocator.create(rendering.Backend) catch |err| std.debug.panic("Failed to allocate rendering backend: {}", .{err});
    defer global.global_allocator.destroy(renderer);

    renderer.* = rendering.Backend.init(global.global_allocator) catch |err| std.debug.panic("Failed to init rendering backend: {}", .{err});
    defer renderer.deinit();

    //Prepare for first render call
    render_signals.render_done_semaphore.post();

    while (true) {
        render_signals.start_render_semphore.wait();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }

        renderer.clear_framebuffer();

        const DefaultCamera: Camera = .{};
        if (render_state.scene) |scene| {
            renderer.render_scene(context.getWindowSize() catch |err| std.debug.panic("Failed to get window size: {}", .{err}), scene, if (render_state.camera) |camera| &camera else &DefaultCamera);
        }

        //TODO: render here
        context.swapWindow();

        render_signals.render_done_semaphore.post();
        if (render_signals.quit_thread.load(.monotonic)) {
            return; //TODO: deinit
        }
    }
}

// const asset = @import("../asset.zig");

// const StaticMeshInstance = struct {
//     transform: Transform,
//     mesh: asset.MeshAssetHandle,
//     materials: std.BoundedArray(asset.MaterialAssetHandle, 16),
// };

// const Scene = struct {
//     instances: std.ArrayList(StaticMeshInstance),
//     skybox: ?asset.TextureAssetHandle = null,
// };

// const Mesh = @import("../platform/opengl/mesh.zig");
// const Texture = @import("../platform/opengl/texture.zig");

// pub const Material = struct {
//     base_color_texture: ?asset.AssetHandle = null,
//     base_color_factor: [4]f32 = [_]f32{1.0} ** 4,

//     metallic_roughness_texture: ?asset.AssetHandle = null,
//     metallic_roughness_factor: [2]f32 = .{ 0.0, 1.0 },

//     emissive_texture: ?asset.AssetHandle = null,
//     emissive_factor: [3]f32 = [_]f32{1.0} ** 3,

//     occlusion_texture: ?asset.AssetHandle = null,
//     normal_texture: ?asset.AssetHandle = null,
// };

// const LoadedAsset = struct {
//     const Self = @This();

//     static_meshes: std.AutoArrayHashMap(asset.AssetHandle, Mesh),
//     textures: std.AutoArrayHashMap(asset.AssetHandle, Texture),
//     materials: std.AutoArrayHashMap(asset.AssetHandle, Material),

//     pub fn init(allocator: std.mem.Allocator) Self {
//         return .{
//             .static_meshes = std.AutoArrayHashMap(asset.AssetHandle, Mesh).init(allocator),
//             .textures = std.AutoArrayHashMap(asset.AssetHandle, Texture).init(allocator),
//             .materials = std.AutoArrayHashMap(asset.AssetHandle, Material).init(allocator),
//         };
//     }

//     fn deinit(self: *Self) void {
//         var mesh_iter = self.static_meshes.iterator();
//         while (mesh_iter.next()) |entry| {
//             entry.value_ptr.deinit();
//         }

//         var texture_iter = self.textures.iterator();
//         while (texture_iter.next()) |entry| {
//             entry.value_ptr.deinit();
//         }

//         self.static_meshes.deinit();
//         self.textures.deinit();
//         self.materials.deinit();
//     }
// };
