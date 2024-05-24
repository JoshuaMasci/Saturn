const std = @import("std");
const zm = @import("zmath");
const imgui = @import("zimgui");

const rendering_system = @import("rendering.zig");
const physics_system = @import("physics.zig");

const input = @import("input.zig");
const world = @import("world.zig");
const Transform = @import("transform.zig");
const camera = @import("camera.zig");
const debug_camera = @import("debug_camera.zig");

const sdl_platform = @import("platform/sdl3.zig");

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    platform: sdl_platform.Platform,

    game_renderer: rendering_system.Renderer,
    game_scene: rendering_system.Scene,
    game_cube: ?rendering_system.SceneInstanceHandle,
    game_camera: debug_camera.DebugCamera,

    game_physics: physics_system.World,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const node: world.Node = undefined;
        var node_pool = world.NodePool.init(allocator);
        defer node_pool.deinit();

        const node_handle = try node_pool.insert(node);
        _ = try node_pool.remove(node_handle);

        const platform = try sdl_platform.Platform.init_window(allocator, "Saturn Engine", .{ .windowed = .{ 1920, 1080 } });

        var game_renderer = try rendering_system.Renderer.init(allocator);
        var game_scene = game_renderer.create_scene();

        var game_camera = debug_camera.DebugCamera.Default;
        game_camera.transform.position = zm.f32x4(0.0, 0.0, -5.0, 0.0);

        // Load resources from gltf file
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);
        if (args.len > 1) {
            const file_path = args[1];
            load_gltf_scene(allocator, &game_renderer, &game_scene, file_path) catch |err| {
                std.log.err("Loading {s} failed with {}", .{ file_path, err });
            };
        }

        try physics_system.init(allocator);
        var game_physics = try physics_system.World.init(
            allocator,
            .{
                .max_bodies = 1024,
                .num_body_mutexes = 0,
                .max_body_pairs = 1024,
                .max_contact_constraints = 1024,
            },
        );

        const floor_shape_settings = try physics_system.create_box(zm.loadArr3(.{ 100.0, 1.0, 100.0 }));
        defer floor_shape_settings.release();

        const floor_shape = try floor_shape_settings.createShape();
        defer floor_shape.release();

        _ = try game_physics.create_body(
            .{ .position = zm.loadArr3(.{ 0.0, -5.0, 0.0 }) },
            floor_shape,
            .static,
        );

        return .{
            .should_quit = false,
            .allocator = allocator,

            .platform = platform,

            .game_renderer = game_renderer,
            .game_scene = game_scene,
            .game_cube = null,
            .game_camera = game_camera,

            .game_physics = game_physics,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_physics.deinit();
        physics_system.deinit();

        if (self.game_cube) |instance| {
            self.game_scene.remove_instance(instance) catch {}; //Do Nothing since we will be destroying it anyways

        }

        self.game_scene.deinit();
        self.game_renderer.deinit();

        self.platform.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !(self.should_quit or self.platform.should_quit);
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?struct { value: usize, unit_str: []const u8 }) !void {
        self.platform.proccess_events(self);

        self.game_camera.update(delta_time);

        try self.game_physics.update(delta_time);

        self.game_renderer.clear_framebuffer();

        var scene_camera = camera.Camera{
            .data = self.game_camera.camera,
            .transform = self.game_camera.transform,
        };

        const window_size = try self.platform.get_window_size();
        self.game_renderer.render_scene(window_size, &self.game_scene, &scene_camera);

        {
            imgui.backend.newFrame(try self.platform.get_window_size());

            if (imgui.begin("Performance", .{})) {
                imgui.text("Delta Time {d:.3}", .{delta_time * 1000});
                imgui.text("FPS {d:.3}", .{1.0 / delta_time});
                if (mem_usage_opt) |mem_usage| {
                    imgui.text("Memory Usage {} {s}", .{ mem_usage.value, mem_usage.unit_str });
                }
            }
            imgui.end();

            imgui.backend.draw();
        }
        self.platform.gl_swap_window();
    }

    pub fn on_button_event(self: *Self, event: input.ButtonEvent) void {
        //std.log.info("Button {} -> {}", .{ event.button, event.state });
        self.game_camera.on_button_event(event);
    }

    pub fn on_axis_event(self: *Self, event: input.AxisEvent) void {
        //std.log.info("Axis {} -> {:.2}", .{ event.axis, event.get_value(false) });
        self.game_camera.on_axis_event(event);
    }
};

const gltf = @import("gltf.zig");

fn load_gltf_scene(allocator: std.mem.Allocator, backend: *rendering_system.Renderer, game_scene: *rendering_system.Scene, file_path: [:0]const u8) !void {
    var resources = try gltf.load(allocator, backend, file_path);
    defer resources.deinit();

    if (resources.default_scene) |default_scene_index| {
        if (resources.scenes.items[default_scene_index]) |*default_scene| {
            for (default_scene.root_nodes.items) |root_node| {
                load_gltf_node(game_scene, &resources, default_scene, root_node);
            }
        }
    }
}

fn load_gltf_node(game_scene: *rendering_system.Scene, resources: *gltf.Resources, scene: *const gltf.Scene, node_handle: gltf.NodeHandle) void {
    if (scene.pool.getPtr(node_handle)) |node| {
        if (node.model) |model| {
            const mesh = resources.meshes.items[model.mesh].?;
            const material = resources.materials.items[model.materials.items[0]].?;
            _ = game_scene.add_instace(mesh, material, &node.transform) catch |err| {
                std.log.err("failed to add scene instance {}", .{err});
            };
        }

        for (node.children.items) |child| {
            load_gltf_node(game_scene, resources, scene, child);
        }
    }
}
