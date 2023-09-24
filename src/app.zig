const std = @import("std");
const log = std.log;
const c = @import("c.zig");

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

pub const App = struct {
    const Self = @This();

    should_quit: bool,
    allocator: std.mem.Allocator,

    window: ?*c.SDL_Window,
    gl_context: c.SDL_GLContext,

    input_system: *input.InputSystem,
    sdl_input_system: *sdl_input.SdlInputSystem,

    game_renderer: renderer.Renderer,
    game_scene: renderer.SceneData,

    pub fn init(allocator: std.mem.Allocator) !Self {
        log.info("Starting SDL2", .{});
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_JOYSTICK | c.SDL_INIT_GAMECONTROLLER | c.SDL_INIT_HAPTIC) != 0) {
            std.debug.panic("SDL ERROR {s}", .{c.SDL_GetError()});
        }

        var window = c.SDL_CreateWindow("Saturn Engine", 0, 0, 1920, 1080, c.SDL_WINDOW_MAXIMIZED | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_OPENGL);

        _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 6);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);

        var gl_context = c.SDL_GL_CreateContext(window);
        _ = c.gladLoadGLLoader(c.SDL_GL_GetProcAddress);

        log.info("Opengl Context:\n\tVender: {s}\n\tRenderer: {s}\n\tVersion: {s}\n\tGLSL: {s}", .{
            c.glGetString(c.GL_VENDOR),
            c.glGetString(c.GL_RENDERER),
            c.glGetString(c.GL_VERSION),
            c.glGetString(c.GL_SHADING_LANGUAGE_VERSION),
        });

        _ = c.SDL_GL_SetSwapInterval(1);

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
            game_context.button_bindings[c.SDL_SCANCODE_SPACE] = button_binding;
            keyboard.context_bindings.put(GameInputContext.name.hash, game_context) catch std.debug.panic("Hashmap put failed", .{});
        }

        var game_renderer = try renderer.Renderer.init();

        var cube_mesh = try game_renderer.load_mesh("some/resource/path/cube.mesh");
        var cube_material = try game_renderer.load_material("some/resource/path/cube.material");
        var cube_tranform = renderer.Transform{};

        var game_scene = try renderer.SceneData.init();

        _ = game_scene.add_instace(cube_mesh, cube_material, &cube_tranform);

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

        c.SDL_GL_DeleteContext(self.gl_context);

        c.SDL_DestroyWindow(self.window);

        log.info("Shutting Down SDL2", .{});
        c.SDL_Quit();
    }

    pub fn is_running(self: Self) bool {
        return !self.should_quit;
    }

    pub fn update(self: *Self) !void {
        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event) != 0) {
            try self.sdl_input_system.proccess_event(&sdl_event);
            switch (sdl_event.type) {
                c.SDL_QUIT => self.should_quit = true,
                else => {},
            }
        }

        self.game_renderer.render_scene(&self.game_scene, &renderer.Transform{});

        c.glClearColor(0.0, 0.0, 0.0, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        c.SDL_GL_SwapWindow(self.window);
    }
};
