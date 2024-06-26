const std = @import("std");
const zm = @import("zmath");
const imgui = @import("zimgui");

const sdl_platform = @import("platform/sdl3.zig");
const rendering_system = @import("rendering.zig");
const physics_system = @import("physics.zig");

const input = @import("input.zig");
const world = @import("world.zig");
const Transform = @import("transform.zig");
const camera = @import("camera.zig");
const debug_camera = @import("debug_camera.zig");

const gltf = @import("gltf.zig");
const proc = @import("procedural.zig");

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    platform: sdl_platform.Platform,
    rendering_backend: rendering_system.Backend,

    game_world: world.World,
    game_camera: debug_camera.DebugCamera,
    game_character: ?world.CharacterHandle,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const platform = try sdl_platform.Platform.init_window(allocator, "Saturn Engine", .{ .windowed = .{ 1920, 1080 } });

        var rendering_backend = try rendering_system.Backend.init(allocator);
        try physics_system.init(allocator);

        var game_world = world.World.init(allocator, &rendering_backend);

        var game_character: ?world.CharacterHandle = null;
        {
            const CharacterHeight: f32 = 0.9;
            const CharacterRadius: f32 = 0.45;

            const shape = try physics_system.create_capsule(CharacterHeight, CharacterRadius);
            const mesh = try proc.create_capsule_mesh(allocator, &rendering_backend, CharacterHeight, CharacterRadius);
            const material = try proc.create_color_material(&rendering_backend, .{ 1.0, 0.0, 1.0, 1.0 });
            const character_handle = try game_world.add_character(&.{ .position = zm.f32x4(5.0, 10.0, 0.0, 0.0) }, shape, .{ .mesh = mesh, .material = material });
            game_character = character_handle;
        }

        //Floor
        _ = try add_cube(allocator, &rendering_backend, &game_world, .{ 1.0, 0.412, 0.38, 1.0 }, .{ 160.0, 0.5, 160.0 }, &.{ .position = zm.f32x4(0.0, -5.0, 0.0, 0.0) }, false);

        //Cube
        _ = try add_cube(allocator, &rendering_backend, &game_world, .{ 0.38, 0.412, 1.0, 1.0 }, .{1.0} ** 3, &.{ .rotation = zm.f32x4(0.505526, 0.706494, -0.312048, 0.384623) }, true);

        // Load resources from gltf file
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);
        if (args.len > 1) {
            const file_path = args[1];
            load_gltf_scene(allocator, &rendering_backend, &game_world, file_path) catch |err| {
                std.log.err("Loading {s} failed with {}", .{ file_path, err });
            };
        }

        var game_camera = debug_camera.DebugCamera.Default;
        game_camera.transform.position = zm.f32x4(0.0, 0.0, -10.0, 0.0);

        return .{
            .should_quit = false,
            .allocator = allocator,

            .platform = platform,

            .game_world = game_world,

            .rendering_backend = rendering_backend,
            .game_camera = game_camera,
            .game_character = game_character,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_world.deinit();

        physics_system.deinit();
        self.rendering_backend.deinit();
        self.platform.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !(self.should_quit or self.platform.should_quit);
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?struct { value: usize, unit_str: []const u8 }) !void {
        self.platform.proccess_events(self);

        self.game_camera.update(delta_time);
        self.game_world.update(delta_time);

        self.rendering_backend.clear_framebuffer();

        var scene_camera = camera.Camera{
            .data = self.game_camera.camera,
            .transform = self.game_camera.transform,
        };

        const window_size = try self.platform.get_window_size();
        self.rendering_backend.render_scene(window_size, &self.game_world.rendering_world, &scene_camera);

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

fn load_gltf_scene(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend, game_world: *world.World, file_path: [:0]const u8) !void {
    var resources = try gltf.load(allocator, rendering_backend, file_path);
    defer resources.deinit();

    if (resources.default_scene) |default_scene_index| {
        if (resources.scenes.items[default_scene_index]) |*default_scene| {
            for (default_scene.root_nodes.items) |root_node| {
                load_gltf_node(game_world, &resources, default_scene, root_node);
            }
        }
    }
}

fn load_gltf_node(game_world: *world.World, resources: *gltf.Resources, scene: *const gltf.Scene, node_handle: gltf.NodeHandle) void {
    if (scene.pool.getPtr(node_handle)) |node| {
        if (node.model) |model| {
            const mesh = resources.meshes.items[model.mesh].?;
            const material = resources.materials.items[model.materials.items[0]].?;
            _ = game_world.add_entity(
                &node.transform,
                null,
                .{
                    .mesh = mesh,
                    .material = material,
                },
            ) catch |err| {
                std.log.err("failed to add scene instance {}", .{err});
            };
        }

        for (node.children.items) |child| {
            load_gltf_node(game_world, resources, scene, child);
        }
    }
}

fn add_cube(allocator: std.mem.Allocator, rendering_backend: *rendering_system.Backend, game_world: *world.World, color: [4]f32, size: [3]f32, transform: *const Transform, dynamic: bool) !world.EntityHandle {
    const mesh = try proc.create_cube_mesh(allocator, rendering_backend, size);
    const material = try proc.create_color_material(rendering_backend, color);
    const shape = try physics_system.create_box(zm.loadArr3(size) * zm.f32x4s(0.5));
    defer shape.release();
    return game_world.add_entity(
        transform,
        .{ .shape = shape, .dynamic = dynamic },
        .{ .mesh = mesh, .material = material },
    );
}
