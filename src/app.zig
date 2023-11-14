const std = @import("std");
const sdl = @import("zsdl");
const c = @import("c.zig");

const zm = @import("zmath");

const StringHash = @import("string_hash.zig");
const input = @import("input.zig");
const sdl_input = @import("sdl_input.zig");

const renderer = @import("renderer.zig");

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

    window: *sdl.Window,
    gl_context: sdl.gl.Context,

    input_system: *input.InputSystem,
    sdl_input_system: *sdl_input.SdlInputSystem,

    game_renderer: renderer.Renderer,
    game_scene: renderer.Scene,

    //Used cause I have no idea how to use the pub zig version for glam
    extern fn SDL_GL_GetProcAddress(proc: ?[*:0]const u8) ?*anyopaque;

    pub fn init(allocator: std.mem.Allocator) !Self {
        std.log.info("Starting SDL2", .{});

        try sdl.init(.{ .video = true, .joystick = true, .gamecontroller = true, .haptic = true });

        var window = try sdl.Window.create(
            "Saturn Engine",
            sdl.Window.pos_undefined,
            sdl.Window.pos_undefined,
            1920,
            1080,
            .{ .maximized = true, .resizable = true, .allow_highdpi = true, .opengl = true },
        );

        try sdl.gl.setAttribute(sdl.gl.Attr.doublebuffer, 1);
        try sdl.gl.setAttribute(sdl.gl.Attr.context_major_version, 4);
        try sdl.gl.setAttribute(sdl.gl.Attr.context_minor_version, 6);
        try sdl.gl.setAttribute(sdl.gl.Attr.context_profile_mask, @intFromEnum(sdl.gl.Profile.core));

        var gl_context = try sdl.gl.createContext(window);

        _ = c.gladLoadGLLoader(&SDL_GL_GetProcAddress);

        std.log.info("Opengl Context:\n\tVender: {s}\n\tRenderer: {s}\n\tVersion: {s}\n\tGLSL: {s}", .{
            c.glGetString(c.GL_VENDOR),
            c.glGetString(c.GL_RENDERER),
            c.glGetString(c.GL_VERSION),
            c.glGetString(c.GL_SHADING_LANGUAGE_VERSION),
        });

        try sdl.gl.setSwapInterval(1);

        var input_system = try allocator.create(input.InputSystem);
        input_system.* = try input.InputSystem.init(
            allocator,
            &[_]input.InputContext{GameInputContext},
        );

        var sdl_input_system = try allocator.create(sdl_input.SdlInputSystem);
        sdl_input_system.* = sdl_input.SdlInputSystem.new(allocator, input_system);

        if (sdl_input_system.keyboard) |*keyboard| {
            var game_context = sdl_input.SdlKeyboardContextBinding.default();
            var button_binding = sdl_input.SdlButtonBinding{
                .target = StringHash.new("Button1"),
            };
            game_context.button_bindings[@intFromEnum(sdl.Scancode.space)] = button_binding;
            try keyboard.context_bindings.put(GameInputContext.name.hash, game_context);
        }

        var game_renderer = try renderer.Renderer.init(allocator);
        var game_scene = game_renderer.create_scene();

        var cube_mesh = try game_renderer.load_mesh("some/resource/path/cube.mesh");
        var cube_material = try game_renderer.load_material("some/resource/path/cube.material");
        var cube_tranform = Transform.Identity;
        cube_tranform.position = zm.f32x4(0.0, 0.0, 5.0, 0.0);

        _ = try game_scene.add_instace(cube_mesh, cube_material, &cube_tranform);

        return .{
            .should_quit = false,
            .allocator = allocator,

            .window = window,
            .gl_context = gl_context,

            .input_system = input_system,
            .sdl_input_system = sdl_input_system,

            .game_renderer = game_renderer,
            .game_scene = game_scene,
        };
    }

    pub fn deinit(self: *Self) void {
        self.game_scene.deinit();
        self.game_renderer.deinit();

        self.sdl_input_system.deinit();
        self.allocator.destroy(self.sdl_input_system);

        self.input_system.deinit();
        self.allocator.destroy(self.input_system);

        sdl.gl.deleteContext(self.gl_context);
        sdl.Window.destroy(self.window);

        std.log.info("Shutting Down SDL2", .{});
        sdl.quit();
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

        self.game_renderer.render_scene(&self.game_scene, &camera);

        sdl.gl.swapWindow(self.window);
    }
};
