const std = @import("std");
const sdl = @import("zsdl2");
const c = @import("c.zig");

const sdl_platform = @import("platform/sdl2.zig");
const zm = @import("zmath");

const StringHash = @import("string_hash.zig");
const input = @import("input.zig");
const sdl_input = @import("sdl_input.zig");

const renderer = @import("renderer/renderer.zig");

pub const GameInputContext = input.InputContext{
    .name = StringHash.new("Game"),
    .buttons = &[_]StringHash{StringHash.new("Button1")},
    .axes = &[_]StringHash{StringHash.new("Axis1")},
};

const world = @import("world.zig");

const Transform = @import("transform.zig");

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    platform: sdl_platform.Platform,

    input_system: *input.InputSystem,
    sdl_input_system: *sdl_input.SdlInputSystem,

    game_renderer: renderer.Renderer,
    game_scene: renderer.Scene,
    game_cube: renderer.SceneInstanceHandle,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const node: world.Node = undefined;
        var node_pool = world.NodePool.init(allocator);
        defer node_pool.deinit();

        const node_handle = try node_pool.insert(node);
        _ = try node_pool.remove(node_handle);

        std.log.info("Starting SDL2", .{});
        const platform = try sdl_platform.Platform.init_window("Saturn Engine", .{ .windowed = .{ 1920, 1080 } });

        const input_system = try allocator.create(input.InputSystem);
        input_system.* = try input.InputSystem.init(
            allocator,
            &[_]input.InputContext{GameInputContext},
        );

        var sdl_input_system = try allocator.create(sdl_input.SdlInputSystem);
        sdl_input_system.* = sdl_input.SdlInputSystem.new(allocator, input_system);

        if (sdl_input_system.keyboard) |*keyboard| {
            var game_context = sdl_input.SdlKeyboardContextBinding.default();
            const button_binding = sdl_input.SdlButtonBinding{
                .target = StringHash.new("Button1"),
            };
            game_context.button_bindings[@intFromEnum(sdl.Scancode.space)] = button_binding;
            try keyboard.context_bindings.put(GameInputContext.name.hash, game_context);
        }

        var game_renderer = try renderer.Renderer.init(allocator);
        var game_scene = game_renderer.create_scene();

        const cube_mesh = try game_renderer.load_static_mesh("some/resource/path/cube.mesh");
        const cube_material = try game_renderer.load_material("some/resource/path/cube.material");
        var cube_tranform = Transform.Identity;
        cube_tranform.position = zm.f32x4(0.0, 0.0, 5.0, 0.0);

        const game_cube = try game_scene.add_instace(cube_mesh, cube_material, &cube_tranform);
        game_scene.update_instance(game_cube, &cube_tranform);

        return .{
            .should_quit = false,
            .allocator = allocator,

            .platform = platform,

            .input_system = input_system,
            .sdl_input_system = sdl_input_system,

            .game_renderer = game_renderer,
            .game_scene = game_scene,
            .game_cube = game_cube,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_scene.remove_instance(self.game_cube) catch {}; //Do Nothing since we will be destroying it anyways

        self.game_scene.deinit();
        self.game_renderer.deinit();

        self.sdl_input_system.deinit();
        self.allocator.destroy(self.sdl_input_system);

        self.input_system.deinit();
        self.allocator.destroy(self.input_system);

        std.log.info("Shutting Down SDL2", .{});
        self.platform.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !self.should_quit;
    }

    pub fn update(self: *Self) !void {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            try self.sdl_input_system.proccess_event(event);
            switch (event.type) {
                .quit => self.should_quit = true,
                else => {},
            }
        }

        c.glClearColor(0.0, 0.0, 0.0, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        var camera = renderer.Camera{
            .data = renderer.PerspectiveCamera.Default,
            .transform = Transform.Identity,
        };

        const window_size = try self.platform.get_window_size();
        c.glViewport(0, 0, window_size[0], window_size[1]);
        self.game_renderer.render_scene(window_size, &self.game_scene, &camera);

        self.platform.gl_swap_window();
    }
};
