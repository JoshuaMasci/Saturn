const std = @import("std");

const physics_system = @import("physics");
const zlua = @import("zlua");
const zm = @import("zmath");
const global = @import("global.zig");
const Imgui = @import("imgui.zig");
const kiss = @import("kiss.zig");
const sdl3 = @import("platform/sdl3.zig");
const PlatformInput = sdl3.Input;
const Window = sdl3.Window;
const RenderThread = @import("rendering/render_thread.zig").RenderThread;

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

pub const App = struct {
    const Self = @This();

    should_quit: bool,

    platform_input: PlatformInput,
    window: Window,
    render_thread: RenderThread,
    render_physics_debug: bool = true,
    imgui: Imgui,
    temp_allocator: std.heap.ArenaAllocator,

    lua: *zlua.Lua,
    world: kiss.World,

    timer: f32 = 0,
    frames: f32 = 0,
    average_dt: f32 = 0.0,

    pub fn init() !Self {
        try global.asset_registry.addRepository("engine", "zig-out/assets");
        try global.asset_registry.addRepository("game", "zig-out/game-assets");

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

        try @import("lua/math.zig").addBindings(lua);

        lua.openMath();

        //Override print function
        lua.pushFunction(zlua.wrap(luaLogInfo));
        lua.setGlobal("print");

        lua.pushFunction(zlua.wrap(luaLogInfo));
        lua.setGlobal("log_info");

        const REAL_EARTH_DENSITY_KG_M3: f32 = 5514.0;
        const PLANET_DENSITY_KG_M3: f32 = REAL_EARTH_DENSITY_KG_M3 * 1000.0;
        const SUN_DENSITY_KG_M3: f32 = PLANET_DENSITY_KG_M3 * 100.0;

        var new_world: kiss.World = .init();

        new_world.addPlanet(.{}, .{ 0.0, 0.0, 0.0, 0.0 }, .dynamic, 25.0, SUN_DENSITY_KG_M3 * 10);
        const sun_mass = new_world.entites.buffer[0].collider.?.getMassProperties().mass;

        const orbital_speed = kiss.calcOrbitalVelocity(sun_mass, 50.0);
        const orbital_velocity = zm.normalize3(zm.f32x4(1.0, 0.5, 0.0, 0.0)) * zm.splat(zm.Vec, orbital_speed);
        new_world.addPlanet(.{ .position = .{ 0.0, 0.0, 50.0, 0.0 } }, orbital_velocity, .dynamic, 5.0, PLANET_DENSITY_KG_M3);
        try new_world.addShip(
            global.global_allocator,
            global.asset_registry,
            .{ .position = .{ 0.0, 0.0, -50.0, 0.0 } },
            orbital_velocity * zm.splat(zm.Vec, -1.0),
        );

        return .{
            .should_quit = false,
            .platform_input = platform_input,
            .window = window,
            .render_thread = render_thread,
            .imgui = imgui,
            .temp_allocator = .init(global.global_allocator),

            .lua = lua,
            .world = new_world,
        };
    }

    pub fn deinit(self: *Self) void {
        self.render_thread.quit();

        self.world.deinit();
        self.lua.deinit();

        physics_system.deinitDebugRenderer();
        physics_system.deinit();

        self.temp_allocator.deinit();

        self.imgui.deinit();

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

        try self.platform_input.proccessEvents(
            .{},
            .{
                .data = @ptrCast(self),
                .resize = window_resize,
                .close_requested = window_close_requested,
            },
        );
        self.imgui.updateInput(&self.platform_input);

        self.world.update(delta_time, &self.platform_input);

        self.render_thread.beginFrame();

        {
            const window_size = self.window.getSize();
            self.imgui.startFrame(window_size, delta_time);
            defer self.imgui.context.endFrame();

            if (self.imgui.context.begin("Performance", null, .{})) {
                self.imgui.context.textFmt("Delta Time {d:.3} ms", .{self.average_dt * 1000});
                self.imgui.context.textFmt("FPS {d:.3}", .{1.0 / self.average_dt});
                if (mem_usage_opt) |mem_usage| {
                    const formatted_string: ?[]const u8 = @import("utils.zig").formatBytes(frame_allocator, mem_usage) catch null;
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

            if (self.imgui.context.begin("Entities", null, .{})) {
                for (self.world.entites.slice(), 0..) |entity, i| {
                    self.imgui.context.textFmt("Entity {} Velocity: {d:.3}", .{ i, zm.length3(entity.rigid_body.linear_velocity)[0] });
                }
            }
            self.imgui.context.end();
        }

        self.render_thread.data.draw_scene = null;
        {
            const rendering = @import("rendering/scene.zig");
            const zphysics = @import("physics");

            var scene: rendering.RenderScene = .init(self.render_thread.data.temp_allocator.allocator());
            self.world.buildScene(&scene);

            var camera_pos: zm.Vec = .{ 0.0, 0.0, -200.0, 0.0 };

            if (self.world.entites.len > 0) {
                camera_pos = self.world.entites.get(0).transform.position + camera_pos;
            }

            self.render_thread.data.draw_scene = .{
                .scene = scene,
                .camera = .Default,
                .camera_transform = .{ .position = camera_pos },
                .debug_physics_draw = self.render_physics_debug,
            };

            if (self.render_physics_debug) {
                var ignore_list = std.BoundedArray(zphysics.Body, 8).init(0) catch unreachable;

                self.render_thread.data.physics_renderer.buildFrame(&self.world.physics_world, .{}, ignore_list.slice());
            }
        }

        self.render_thread.submitFrame();
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
