const std = @import("std");

const App = @import("../app.zig").App;
const Settings = @import("../rendering/settings.zig");

const Controller = @import("sdl3/controller.zig");

pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cInclude("SDL3/SDL_vulkan.h");

    @cDefine("SDL_MAIN_HANDLED", {});
});

pub fn init(allocator: std.mem.Allocator) !void {
    _ = allocator; // autofix
    if (!c.SDL_Init(c.SDL_INIT_EVENTS | c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD | c.SDL_INIT_HAPTIC)) {
        return error.sdlInitFailed;
    }

    const version = c.SDL_GetVersion();
    std.log.info("Starting sdl {}.{}.{}", .{ c.SDL_VERSIONNUM_MAJOR(version), c.SDL_VERSIONNUM_MINOR(version), c.SDL_VERSIONNUM_MICRO(version) });

    if (c.SDL_GetCurrentVideoDriver()) |driver| {
        std.log.info("SDL3 using {s} backend", .{driver});
    }
}

pub fn deinit() void {
    std.log.info("Quiting sdl", .{});
    c.SDL_Quit();
}

pub const Window = struct {
    const Self = @This();

    handle: *c.SDL_Window,

    pub fn init(name: [:0]const u8, size: Settings.WindowSize) Self {
        var window_width: i32 = 1600;
        var window_height: i32 = 900;
        var window_flags = c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_VULKAN;

        switch (size) {
            .windowed => |window_size| {
                window_width = window_size[0];
                window_height = window_size[1];
            },
            .maximized => window_flags |= c.SDL_WINDOW_MAXIMIZED,
            .fullscreen => window_flags |= c.SDL_WINDOW_FULLSCREEN,
        }

        const handle = c.SDL_CreateWindow(name, window_width, window_height, window_flags).?;

        return .{ .handle = handle };
    }

    pub fn deinit(self: *Self) void {
        _ = c.SDL_DestroyWindowSurface(self.handle);
    }

    pub fn getSize(self: @This()) [2]u32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSize(self.handle, &w, &h);
        return .{ @intCast(w), @intCast(h) };
    }
};

pub const WindowCallbacks = struct {
    data: ?*anyopaque = null,
    resize: ?*const fn (data: ?*anyopaque, window: Window, size: [2]u32) void = null,
    close_requested: ?*const fn (data: ?*anyopaque, window: Window) void = null,
};

pub const Input = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    should_quit: bool,
    keyboard: ?*Keyboard = null,
    mouse: ?*Mouse = null,
    controllers: std.AutoArrayHashMap(c.SDL_JoystickID, *Controller),

    pub fn init(allocator: std.mem.Allocator) !Self {
        var keyboard: ?*Keyboard = null;
        if (c.SDL_HasKeyboard()) {
            keyboard = try allocator.create(Keyboard);
            keyboard.?.* = Keyboard{};
        } else {
            std.log.err("No Keyboard", .{});
        }

        var mouse: ?*Mouse = null;
        if (c.SDL_HasMouse()) {
            mouse = try allocator.create(Mouse);
            mouse.?.* = Mouse{};
        } else {
            std.log.err("No Mouse", .{});
        }

        const controllers = std.AutoArrayHashMap(c.SDL_JoystickID, *Controller).init(allocator);

        return .{
            .allocator = allocator,
            .should_quit = false,
            .keyboard = keyboard,
            .mouse = mouse,
            .controllers = controllers,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.controllers.values()) |controller| {
            controller.deinit();
            self.allocator.destroy(controller);
        }
        self.controllers.deinit();

        if (self.keyboard) |keyboard| {
            self.allocator.destroy(keyboard);
        }
        if (self.mouse) |mouse| {
            self.allocator.destroy(mouse);
        }
    }

    pub fn captureMouse(self: *Self, window: Window) void {
        if (self.mouse) |mouse| {
            mouse.capture(window);
        }
    }

    pub fn releaseMouse(self: *Self) void {
        if (self.mouse) |mouse| {
            mouse.release();
        }
    }

    pub fn isMouseCaptured(self: *Self) bool {
        if (self.mouse) |mouse| {
            return mouse.isCaptured();
        }
        return false;
    }

    pub fn isMousePressed(self: *Self, button: Mouse.Button) bool {
        if (self.mouse) |mouse| {
            return mouse.button_state.get(button).is_pressed and !mouse.button_state.get(button).was_pressed_last_frame;
        }

        return false;
    }

    pub fn isMouseDown(self: *Self, button: Mouse.Button) bool {
        if (self.mouse) |mouse| {
            return mouse.button_state.get(button).is_pressed;
        }

        return false;
    }

    pub fn getMousePosition(self: *Self) ?[2]f32 {
        if (self.mouse) |mouse| {
            _ = mouse; // autofix
            var pos: [2]f32 = @splat(0.0);
            _ = c.SDL_GetMouseState(@ptrCast(&pos[0]), @ptrCast(&pos[1]));
            return pos;
        }
        return null;
    }

    pub fn proccessEvents(self: *Self, window_callbacks: WindowCallbacks) !void {
        if (self.keyboard) |keyboard| {
            keyboard.beginFrame();
        }

        if (self.mouse) |mouse| {
            mouse.beginFrame();
        }

        for (self.controllers.values()) |controller| {
            controller.beginFrame();
        }

        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_WINDOW_RESIZED => {
                    if (window_callbacks.resize) |resize_fn| {
                        if (c.SDL_GetWindowFromID(event.window.windowID)) |handle| {
                            const window: Window = .{ .handle = handle };
                            const size: [2]u32 = .{ @intCast(event.window.data1), @intCast(event.window.data2) };
                            resize_fn(window_callbacks.data, window, size);
                        } else {
                            std.log.warn("SDL_GetWindowFromID Failed for ID({})", .{event.window.windowID});
                        }
                    }
                },
                c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    if (window_callbacks.close_requested) |close_fn| {
                        if (c.SDL_GetWindowFromID(event.window.windowID)) |handle| {
                            const window: Window = .{ .handle = handle };
                            close_fn(window_callbacks.data, window);
                        } else {
                            std.log.warn("SDL_GetWindowFromID Failed for ID({})", .{event.window.windowID});
                        }
                    }
                },
                c.SDL_EVENT_QUIT => {
                    self.should_quit = true;
                },
                c.SDL_EVENT_KEY_UP, c.SDL_EVENT_KEY_DOWN => {
                    // Releases mouse so it can't ever get stuck
                    if (event.key.scancode == c.SDL_SCANCODE_ESCAPE and event.key.down) {
                        self.releaseMouse();
                    }

                    if (self.keyboard) |keyboard| {
                        keyboard.proccessEvent(&event);
                    }
                },
                c.SDL_EVENT_MOUSE_ADDED => {
                    std.log.info("Mouse Added: {}", .{event.mdevice.which});
                },
                c.SDL_EVENT_MOUSE_REMOVED => {
                    std.log.info("Mouse Remove: {}", .{event.mdevice.which});
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_WHEEL, c.SDL_EVENT_MOUSE_MOTION => {
                    if (self.mouse) |mouse| {
                        mouse.proccessEvent(&event);
                    }
                },
                c.SDL_EVENT_GAMEPAD_BUTTON_UP, c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
                    if (self.controllers.get(event.gbutton.which)) |controller| {
                        controller.proccessEvent(&event);
                    }
                },
                c.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
                    if (self.controllers.get(event.gaxis.which)) |controller| {
                        controller.proccessEvent(&event);
                    }
                },
                c.SDL_EVENT_GAMEPAD_ADDED => {
                    if (!self.controllers.contains(event.gdevice.which)) {
                        const controller = try self.allocator.create(Controller);
                        controller.* = try .init(self.allocator, c.SDL_OpenGamepad(event.gdevice.which).?);
                        std.log.info("Gamepad Added: {s}({})", .{ controller.name, event.gdevice.which });

                        try self.controllers.put(controller.joystick, controller);
                    }
                },
                c.SDL_EVENT_GAMEPAD_REMOVED => {
                    if (self.controllers.fetchSwapRemove(event.gdevice.which)) |entry| {
                        std.log.info("Gamepad Removed: {s}({})", .{ entry.value.name, event.gdevice.which });
                        entry.value.deinit();
                        self.allocator.destroy(entry.value);
                    }
                },
                else => {},
            }
        }
    }
};

pub const ButtonState = struct {
    timestamp: u64 = 0,
    is_pressed: bool = false,
    was_pressed_last_frame: bool = false,
};

pub const AxisState = struct {
    timestamp: u64 = 0,
    value: f32 = 0.0,
};

const Keyboard = struct {
    const Self = @This();

    button_state: [c.SDL_SCANCODE_COUNT]ButtonState = @splat(.{}),

    fn beginFrame(self: *Self) void {
        for (&self.button_state) |*button_state| {
            button_state.was_pressed_last_frame = button_state.is_pressed;
        }
    }

    fn proccessEvent(self: *Self, event: *c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_KEY_UP, c.SDL_EVENT_KEY_DOWN => {
                self.button_state[event.key.scancode].timestamp = event.key.timestamp;
                self.button_state[event.key.scancode].is_pressed = event.key.down;
            },
            else => {},
        }
    }
};

const MouseMovementState = union(enum) {
    active: [2]AxisState, // Currently moving this frame
    previous: void, // Moved in the last frame, not this one
    idle: void, // No recent movement
};

const Mouse = struct {
    const Self = @This();

    const Button = enum(u32) {
        left = c.SDL_BUTTON_LEFT,
        middle = c.SDL_BUTTON_MIDDLE,
        right = c.SDL_BUTTON_RIGHT,
        extra1 = c.SDL_BUTTON_X1,
        extra2 = c.SDL_BUTTON_X2,
    };

    button_state: std.EnumArray(Button, ButtonState) = .initFill(.{}),
    axis_state: MouseMovementState = .idle,

    captured_window: ?Window = null,

    fn isCaptured(self: *Self) bool {
        if (self.captured_window) |window| {
            if (c.SDL_GetWindowRelativeMouseMode(window.handle)) {
                return true;
            }
            self.captured_window = null;
        }

        return false;
    }

    fn capture(self: *Self, window: Window) void {
        if (c.SDL_SetWindowRelativeMouseMode(window.handle, true) == true) {
            self.captured_window = window;
        }
    }

    fn release(self: *Self) void {
        if (self.captured_window) |window| {
            _ = c.SDL_SetWindowRelativeMouseMode(window.handle, false);
            self.captured_window = null;
        }
    }

    fn beginFrame(self: *Self) void {
        for (&self.button_state.values) |*button_state| {
            button_state.was_pressed_last_frame = button_state.is_pressed;
        }

        // Clears mouse movement for this new frame
        // .last is used if the mouse moved last frame, so this frame the mouse axis is reset to 0,0 this frame
        self.axis_state = switch (self.axis_state) {
            .active => |_| .previous,
            .previous => .idle,
            .idle => .idle,
        };
    }

    fn proccessEvent(self: *Self, event: *c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_MOUSE_BUTTON_UP, c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const button = std.meta.intToEnum(Button, event.button.button) catch |err| {
                    std.log.err("Failed to convert int to enum {} value({})", .{ err, event.button.button });
                    return;
                };

                const state = self.button_state.getPtr(button);
                state.timestamp = event.button.timestamp;
                state.is_pressed = event.button.down;
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                const PIXEL_MOVE_AMOUNT = 25.0; //TODO: is this even needed since the xrel is already a float?
                const mouse_move_state: [2]AxisState = .{
                    .{
                        .value = event.motion.xrel / PIXEL_MOVE_AMOUNT,
                        .timestamp = event.motion.timestamp,
                    },
                    .{
                        .value = event.motion.yrel / PIXEL_MOVE_AMOUNT,
                        .timestamp = event.motion.timestamp,
                    },
                };
                self.axis_state = .{ .active = mouse_move_state };
            },
            else => {},
        }
    }
};

pub const Vulkan = struct {
    const vk = @import("vulkan");

    pub fn getProcInstanceFunction() ?vk.PfnGetInstanceProcAddr {
        return @ptrCast(c.SDL_Vulkan_GetVkGetInstanceProcAddr());
    }

    pub fn getInstanceExtensions() []const [*c]const u8 {
        var array_len: u32 = 0;
        const array = c.SDL_Vulkan_GetInstanceExtensions(&array_len);
        return array[0..array_len];
    }

    pub fn createSurface(instance: vk.Instance, window: Window, allocator: ?*const vk.AllocationCallbacks) ?vk.SurfaceKHR {
        var c_surface: c.VkSurfaceKHR = undefined;
        const c_instance: c.VkInstance = @ptrFromInt(@intFromEnum(instance));
        const c_allocator: ?*c.VkAllocationCallbacks = @constCast(@ptrCast(allocator));

        if (c.SDL_Vulkan_CreateSurface(window.handle, c_instance, c_allocator, &c_surface)) {
            const surface: vk.SurfaceKHR = @enumFromInt(@intFromPtr(c_surface));
            return surface;
        }
        return null;
    }

    pub fn destroySurface(instance: vk.Instance, surface: vk.SurfaceKHR, allocator: ?*const vk.AllocationCallbacks) void {
        const c_instance: c.VkInstance = @ptrFromInt(@intFromEnum(instance));
        const c_allocator: ?*c.VkAllocationCallbacks = @constCast(@ptrCast(allocator));
        c.SDL_Vulkan_DestroySurface(c_instance, @ptrFromInt(@intFromEnum(surface)), c_allocator);
    }
};
