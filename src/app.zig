const std = @import("std");

const physics_system = @import("physics");
const zlua = @import("zlua");
const zm = @import("zmath");

const Entity = @import("entity/entity.zig");
const Universe = @import("entity/universe.zig");
const World = @import("entity/world.zig");
const global = @import("global.zig");
const Imgui = @import("imgui.zig");
const sdl3 = @import("platform/sdl3.zig");
const PlatformInput = sdl3.Input;
const Window = sdl3.Window;
const RenderThread = @import("rendering/render_thread.zig").RenderThread;
const world_gen = @import("world_gen.zig");

//Test Lua Code
fn luaLogInfo(lua: *zlua.Lua) !c_int {
    const nargs = lua.getTop();
    const nargs_u: usize = @intCast(nargs);
    var list = std.ArrayList(u8).init(global.global_allocator);
    defer list.deinit();

    for (0..nargs_u) |index| {
        const i: i32 = @intCast(index + 1);
        const s = lua.toString(i) catch "<non-string>";
        _ = try list.appendSlice(s);
    }

    const message = list.items;
    std.log.info("{s}", .{message});

    return 0;
}

fn isControllerButtonDown(lua: *zlua.Lua) !c_int {
    const Controller = @import("platform/sdl3/controller.zig");

    // Get input system
    _ = try lua.getGlobal("input");
    const platform_input = try lua.toUserdata(PlatformInput, -1);

    const arg_count = lua.getTop();
    if (arg_count < 1 or !lua.isString(1)) {
        return error.ExpectedStringArg;
    }
    const string = try lua.toString(1);

    var result: bool = false;

    const controllers = platform_input.controllers.values();
    if (controllers.len > 0) {
        const controller = controllers[0];

        if (std.meta.stringToEnum(Controller.Button, string)) |button| {
            const index = @intFromEnum(button);
            result = controller.button_state[index].is_pressed;
        }
    }

    lua.pushBoolean(result);
    return 1;
}

fn isControllerButtonPressed(lua: *zlua.Lua) !c_int {
    const Controller = @import("platform/sdl3/controller.zig");

    // Get input system
    _ = try lua.getGlobal("input");
    const platform_input = try lua.toUserdata(PlatformInput, -1);

    const arg_count = lua.getTop();
    if (arg_count < 1 or !lua.isString(1)) {
        return error.ExpectedStringArg;
    }
    const string = try lua.toString(1);

    var result: bool = false;

    const controllers = platform_input.controllers.values();
    if (controllers.len > 0) {
        const controller = controllers[0];

        if (std.meta.stringToEnum(Controller.Button, string)) |button| {
            const index = @intFromEnum(button);
            result = controller.button_state[index].is_pressed and !controller.button_state[index].was_pressed_last_frame;
        }
    }

    lua.pushBoolean(result);
    return 1;
}

fn getControllerAxis(lua: *zlua.Lua) !c_int {
    const Controller = @import("platform/sdl3/controller.zig");

    // Get input system
    _ = try lua.getGlobal("input");
    const platform_input = try lua.toUserdata(PlatformInput, -1);

    const arg_count = lua.getTop();
    if (arg_count < 1 or !lua.isString(1)) {
        return error.ExpectedStringArg;
    }
    const string = try lua.toString(1);

    var result: f32 = 0.0;

    const controllers = platform_input.controllers.values();
    if (controllers.len > 0) {
        const controller = controllers[0];

        if (std.meta.stringToEnum(Controller.Axis, string)) |axis| {
            const index = @intFromEnum(axis);
            result = controller.axis_state[index].value;
        }
    }

    lua.pushNumber(result);
    return 1;
}

pub fn setEntityLinearVelocity(lua: *zlua.Lua) !i32 {
    const physics = @import("entity/engine/physics.zig");

    _ = try lua.getGlobal("entity");
    const entity = try lua.toUserdata(Entity, -1);

    const arg_count = lua.getTop();

    if (arg_count != 4) {
        return error.InvalidArgCount;
    }

    const linear_velocity: zm.Vec = .{
        @floatCast(try lua.toNumber(1)),
        @floatCast(try lua.toNumber(2)),
        @floatCast(try lua.toNumber(3)),
        0.0,
    };

    if (entity.systems.get(physics.PhysicsEntitySystem)) |entity_physics| {
        entity_physics.linear_velocity = linear_velocity;
    }

    return 0;
}

pub fn setEntityAngularVelocity(lua: *zlua.Lua) !i32 {
    const physics = @import("entity/engine/physics.zig");

    _ = try lua.getGlobal("entity");
    const entity = try lua.toUserdata(Entity, -1);

    const arg_count = lua.getTop();

    if (arg_count != 4) {
        return error.InvalidArgCount;
    }

    const angular_velocity: zm.Vec = .{
        @floatCast(try lua.toNumber(1)),
        @floatCast(try lua.toNumber(2)),
        @floatCast(try lua.toNumber(3)),
        0.0,
    };

    if (entity.systems.get(physics.PhysicsEntitySystem)) |entity_physics| {
        entity_physics.angular_velocity = angular_velocity;
    }

    return 0;
}

pub fn readFileToZString(allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8) ![:0]u8 {
    const file = try dir.openFile(path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size + 1);

    _ = try file.readAll(buffer[0..file_size]);
    buffer[file_size] = 0;
    return buffer[0..file_size :0];
}

pub const LuaScript = struct {
    code: [:0]const u8, //TODO: use bytecode instead

    fn run(self: @This(), lua: *zlua.Lua) !void {
        errdefer lua.pop(1);

        try lua.loadString(self.code);
        try lua.protectedCall(.{});
    }
};

pub const App = struct {
    const Self = @This();

    should_quit: bool,

    platform_input: PlatformInput,
    window: Window,
    render_thread: RenderThread,
    render_physics_debug: bool = false,
    imgui: Imgui,
    temp_allocator: std.heap.ArenaAllocator,

    lua: *zlua.Lua,
    lua_script: ?LuaScript,

    game_universe: *Universe,
    game_debug_camera: Entity.Handle,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    pub fn init() !Self {
        try global.assets.addDir("engine", "zig-out/assets");
        try global.assets.addDir("game", "zig-out/game-assets");

        try sdl3.init(global.global_allocator);

        const imgui = try Imgui.init(global.global_allocator);
        errdefer imgui.deinit();

        const platform_input = try PlatformInput.init(global.global_allocator);
        const window = Window.init("Saturn Engine", .maximized);
        const render_thread = try RenderThread.init(global.global_allocator, window, imgui.context);

        physics_system.init(global.global_allocator);
        physics_system.initDebugRenderer(render_thread.data.physics_renderer.getDebugRendererData());

        const lua = try zlua.Lua.init(global.global_allocator);
        errdefer lua.deinit();

        lua.openMath();

        //Override print function
        lua.pushFunction(zlua.wrap(luaLogInfo));
        lua.setGlobal("print");

        lua.pushFunction(zlua.wrap(luaLogInfo));
        lua.setGlobal("log_info");

        lua.pushFunction(zlua.wrap(isControllerButtonDown));
        lua.setGlobal("isControllerButtonDown");

        lua.pushFunction(zlua.wrap(isControllerButtonPressed));
        lua.setGlobal("isControllerButtonPressed");

        lua.pushFunction(zlua.wrap(getControllerAxis));
        lua.setGlobal("getControllerAxis");

        lua.pushFunction(zlua.wrap(setEntityLinearVelocity));
        lua.setGlobal("setEntityLinearVelocity");

        lua.pushFunction(zlua.wrap(setEntityAngularVelocity));
        lua.setGlobal("setEntityAngularVelocity");

        const lua_script: LuaScript = .{
            .code = try readFileToZString(global.global_allocator, std.fs.cwd(), "assets/lua_scripts/log_test.lua"),
        };

        const game_universe = try Universe.init(global.global_allocator);
        const game_worlds = try world_gen.create_ship_worlds(global.global_allocator, game_universe);
        const debug_entity = try world_gen.create_debug_camera(game_universe, game_worlds.inside, .{ .position = zm.f32x4(0.0, 0.0, -15.0, 0.0) });
        world_gen.create_props(game_universe, game_worlds.inside, 10, zm.f32x4(2.5, 0.0, -15.0, 0.0), 0.15);

        //try world_gen.loadScene(global.global_allocator, game_universe, game_worlds.inside, "zig-out/game-assets/Sponza/NewSponza_Main_glTF_002/scene.json", .{ .position = zm.f32x4(0, -1, 0, 0) });
        //try world_gen.loadScene(global.global_allocator, game_universe, game_worlds.inside, "zig-out/game-assets/Bistro/scene.json", .{ .position = zm.f32x4(0, -50, 0, 0) });

        return .{
            .should_quit = false,
            .platform_input = platform_input,
            .window = window,
            .render_thread = render_thread,
            .imgui = imgui,
            .temp_allocator = .init(global.global_allocator),

            .lua = lua,
            .lua_script = lua_script,

            .game_universe = game_universe,
            .game_debug_camera = debug_entity,
        };
    }

    pub fn deinit(self: *Self) void {
        self.render_thread.quit();

        self.game_universe.deinit();

        physics_system.deinitDebugRenderer();
        physics_system.deinit();

        self.temp_allocator.deinit();

        self.imgui.deinit();

        if (self.lua_script) |script| {
            global.global_allocator.free(script.code);
        }

        self.lua.deinit();

        self.render_thread.deinit();
        self.window.deinit();
        self.platform_input.deinit();

        sdl3.deinit();
    }

    pub fn is_running(self: Self) bool {
        return !(self.should_quit or self.platform_input.should_quit);
    }

    pub fn update(self: *Self, delta_time: f32, mem_usage_opt: ?usize) !void {
        _ = self.temp_allocator.reset(.retain_capacity);
        const frame_allocator = self.temp_allocator.allocator();

        //New Entity Test
        const entity2 = @import("entity.zig");
        var world: entity2.World = try .init(frame_allocator, "Test World", .{
            .physics = .init(frame_allocator),
        });
        defer world.deinit();

        world.update(delta_time);

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

        try self.platform_input.proccessEvents(.{
            .data = @ptrCast(self),
            .resize = window_resize,
            .close_requested = window_close_requested,
        });
        self.imgui.updateInput(&self.platform_input);

        {
            self.lua.pushLightUserdata(&self.platform_input);
            self.lua.setGlobal("input");

            self.lua.pushLightUserdata(self.game_universe.entities.get(self.game_debug_camera).?);
            self.lua.setGlobal("entity");

            if (self.lua_script) |script| {
                script.run(self.lua) catch |err| {
                    std.log.err("Failed to run Lua Script: {}", .{err});
                };
            }
        }

        self.game_universe.update(.frame_start, delta_time);
        self.game_universe.update(.pre_physics, delta_time);
        self.game_universe.update(.physics, delta_time);
        self.game_universe.update(.post_physics, delta_time);
        self.game_universe.update(.pre_render, delta_time);

        self.render_thread.beginFrame();

        {
            const window_size = self.window.getSize();
            self.imgui.startFrame(window_size, delta_time);
            defer self.imgui.context.endFrame();

            //_ = self.imgui.createFullscreenDockspace("MainDockspace");
            //defer Imgui.imgui.end();

            if (self.imgui.context.begin("Performance", null, .{})) {
                self.imgui.context.textFmt("Delta Time {d:.3} ms", .{self.average_dt * 1000});
                self.imgui.context.textFmt("FPS {d:.3}", .{1.0 / self.average_dt});
                if (mem_usage_opt) |mem_usage| {
                    const formatted_string: ?[]const u8 = @import("utils.zig").format_bytes(frame_allocator, mem_usage) catch null;
                    if (formatted_string) |mem_usage_string| {
                        defer frame_allocator.free(mem_usage_string);
                        self.imgui.context.textFmt("Memory Usage {s}", .{mem_usage_string});
                    }
                }
            }
            self.imgui.context.end();

            if (self.imgui.context.begin("Debug", null, .{})) {
                _ = self.imgui.context.checkbox("Debug Physics Layer", &self.render_physics_debug);
            }
            self.imgui.context.end();

            // if (!self.platform.isMouseCaptured() and
            //     !zimgui.isWindowHovered(.{ .any_window = true }) and
            //     zimgui.isMouseClicked(zimgui.MouseButton.left) and
            //     !zimgui.isAnyItemHovered())
            // {
            //     self.platform.captureMouse(self.window);
            // }
        }

        self.render_thread.data.draw_scene = null;
        if (self.game_universe.entities.get(self.game_debug_camera)) |game_debug_entity| {
            if (game_debug_entity.world) |game_world| {
                const rendering = @import("entity/engine/rendering.zig");
                const physics = @import("entity/engine/physics.zig");
                const zphysics = @import("physics");

                if (game_world.systems.get(rendering.RenderWorldSystem)) |render_world| {
                    self.render_thread.data.draw_scene = .{
                        .camera = .Default,
                        .camera_transform = game_debug_entity.transform,
                        .scene = try render_world.scene.dupe(self.render_thread.data.temp_allocator.allocator()),
                        .debug_physics_draw = self.render_physics_debug,
                    };

                    if (self.render_physics_debug) {
                        if (game_world.systems.get(physics.PhysicsWorldSystem)) |physics_world| {
                            var ignore_list = std.BoundedArray(zphysics.Body, 8).init(0) catch unreachable;

                            if (game_debug_entity.systems.get(physics.PhysicsEntitySystem)) |game_debug_entity_physics| {
                                ignore_list.appendAssumeCapacity(game_debug_entity_physics.body);
                            }

                            self.render_thread.data.physics_renderer.buildFrame(&physics_world.physics_world, .{}, ignore_list.slice());
                        }
                    }
                }
            }
        }

        self.render_thread.submitFrame();

        self.game_universe.update(.frame_end, delta_time);
    }
};

fn window_resize(data: ?*anyopaque, window: Window, size: [2]u32) void {
    _ = size; // autofix
    const app: *App = @alignCast(@ptrCast(data.?));

    //IDK if I should do this here, it probably could cause a race condition
    if (app.render_thread.data.device.swapchains.get(window)) |swapchain| {
        swapchain.swapchain.out_of_date = true;
    }
}

fn window_close_requested(data: ?*anyopaque, window: Window) void {
    const app: *App = @alignCast(@ptrCast(data.?));

    if (app.window.handle == window.handle) {
        std.log.info("Main Window got close request", .{});
        app.should_quit = true;
    }
}
