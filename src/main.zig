const std = @import("std");
const log = std.log;

const c = @cImport({
    @cInclude("SDL.h");
});

pub const StringHash = struct {
    const Self = @This();
    pub const HashType = u32;

    hash: HashType,
    string: []const u8,

    fn new(comptime string: []const u8) Self {
        return .{
            .hash = std.hash.Fnv1a_32.hash(string),
            .string = string,
        };
    }
};
const InputContext = struct {
    name: StringHash,
    buttons: []const StringHash,
    axes: []const StringHash,
};

pub const InputButtonCallback = *const fn (ptr: *anyopaque, button: StringHash, state: ButtonState) void;
pub const InputAxisCallback = *const fn (ptr: *anyopaque, axis: StringHash, value: f32) void;
const InputContextCallback = struct {
    const Self = @This();

    ptr: *anyopaque,
    button_callback: ?InputButtonCallback,
    axis_callback: ?InputAxisCallback,

    pub fn trigger_button(self: Self, button: StringHash, state: ButtonState) void {
        if (self.button_callback) |callback_fn| {
            callback_fn(self.ptr, button, state);
        }
    }
    pub fn trigger_axis(self: Self, axis: StringHash, value: f32) void {
        if (self.axis_callback) |callback| {
            callback(self.ptr, axis, value);
        }
    }
};
const InputSystem = struct {
    const Self = @This();

    const InnerContext = struct {
        context: InputContext,
        callbacks: std.ArrayList(InputContextCallback),
    };
    context_map: std.AutoHashMap(StringHash.HashType, InnerContext),
    active_context: StringHash,

    fn init(allocator: std.mem.Allocator, contexts: []const InputContext) !Self {
        var context_map = std.AutoHashMap(StringHash.HashType, InnerContext).init(allocator);

        for (contexts) |context| {
            var callbacks = std.ArrayList(InputContextCallback).init(allocator);
            try context_map.put(context.name.hash, .{
                .context = context,
                .callbacks = callbacks,
            });
        }

        return Self{
            .context_map = context_map,
            .active_context = contexts[0].name,
        };
    }

    fn deinit(self: *Self) void {
        var iterator = self.context_map.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.callbacks.deinit();
        }
        self.context_map.deinit();
    }

    fn add_callback(self: *Self, context_name: StringHash, callback: InputContextCallback) !void {
        if (self.context_map.getPtr(context_name.hash)) |inner_context| {
            try inner_context.callbacks.append(callback);
        }
    }

    fn set_active_context(self: *Self, context_name: StringHash) void {
        if (self.context_map.contains(context_name.hash)) {
            self.active_context = context_name;
        } else {
            unreachable;
        }
    }

    fn trigger_button(self: *Self, button: StringHash, state: ButtonState) void {
        if (self.context_map.getPtr(self.active_context.hash)) |context| {
            for (context.callbacks.items) |callback| {
                //TODO: verify that button is part of context
                callback.trigger_button(button, state);
            }
        } else {
            unreachable;
        }
    }

    fn trigger_axis(self: *Self, axis: StringHash, value: f32) void {
        if (self.context_map.getPtr(self.active_context.hash)) |context| {
            for (context.callbacks.items) |callback| {
                //TODO: verify that axis is part of context
                callback.trigger_axis(axis, value);
            }
        } else {
            unreachable;
        }
    }
};

pub const ButtonState = enum {
    Pressed,
    Released,
};

pub const SdlControllerButtonBinding = struct {
    target: StringHash,
};
pub const SdlControllerAxisBinding = struct {
    target: StringHash,
    invert: bool,
    deadzone: f32,
    sensitivity: f32,

    pub fn calc_value(self: @This(), value: f32) f32 {
        var value_abs = std.math.clamp(@fabs(value), 0.0, 1.0);
        var value_sign = std.math.sign(value);
        var invert: f32 = switch (self.invert) {
            true => -1.0,
            false => 1.0,
        };
        var value_remap: f32 = switch (value_abs >= self.deadzone) {
            true => (value_abs - self.deadzone) / (1.0 - self.deadzone),
            false => 0.0,
        };
        return value_remap * value_sign * invert * self.sensitivity;
    }
};
pub const SdlControllerContext = struct {
    const Self = @This();

    button_bindings: [c.SDL_CONTROLLER_BUTTON_MAX]?SdlControllerButtonBinding,
    axis_bindings: [c.SDL_CONTROLLER_AXIS_MAX]?SdlControllerAxisBinding,
    pub fn default() @This() {
        return .{
            .button_bindings = [_]?SdlControllerButtonBinding{null} ** c.SDL_CONTROLLER_BUTTON_MAX,
            .axis_bindings = [_]?SdlControllerAxisBinding{null} ** c.SDL_CONTROLLER_AXIS_MAX,
        };
    }

    pub fn get_button_binding(self: Self, index: usize) ?SdlControllerButtonBinding {
        return self.button_bindings[index];
    }

    pub fn get_axis_binding(self: Self, index: usize) ?SdlControllerAxisBinding {
        return self.axis_bindings[index];
    }
};

pub const SdlController = struct {
    const Self = @This();

    name: [*c]const u8,
    handle: *c.SDL_GameController,
    haptic: ?*c.SDL_Haptic,

    context_bindings: std.AutoHashMap(StringHash.HashType, SdlControllerContext),

    pub fn deinit(self: *Self) void {
        if (self.haptic) |haptic| {
            c.SDL_HapticClose(haptic);
        }
        c.SDL_GameControllerClose(self.handle);
        self.context_bindings.deinit();
    }

    pub fn get_button_binding(self: Self, context_hash: StringHash.HashType, index: usize) ?SdlControllerButtonBinding {
        if (self.context_bindings.getPtr(context_hash)) |context| {
            return context.get_button_binding(index);
        }
        return null;
    }

    pub fn get_axis_binding(self: Self, context_hash: StringHash.HashType, index: usize) ?SdlControllerAxisBinding {
        if (self.context_bindings.getPtr(context_hash)) |context| {
            return context.get_axis_binding(index);
        }
        return null;
    }
};

pub const SdlInputSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    controllers: std.AutoHashMap(c.SDL_JoystickID, SdlController),

    input_system: *InputSystem,

    pub fn new(
        allocator: std.mem.Allocator,
        input_system: *InputSystem,
    ) Self {
        return .{
            .allocator = allocator,
            .controllers = std.AutoHashMap(c.SDL_JoystickID, SdlController).init(allocator),
            .input_system = input_system,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.controllers.iterator();
        while (iterator.next()) |controller| {
            controller.value_ptr.deinit();
        }
        self.controllers.deinit();
    }

    pub fn proccess_event(self: *Self, sdl_event: *c.SDL_Event) !void {
        switch (sdl_event.type) {
            c.SDL_CONTROLLERDEVICEADDED => {
                var controller_result: ?*c.SDL_GameController = c.SDL_GameControllerOpen(sdl_event.cdevice.which);
                if (controller_result) |controller_handle| {
                    var controller_name = c.SDL_GameControllerName(controller_handle);
                    log.info("Controller Added Event: {}->{s}", .{ sdl_event.cdevice.which, controller_name });

                    //TODO: load or generate bindings
                    var game_context = SdlControllerContext.default();
                    var button_binding = SdlControllerButtonBinding{
                        .target = StringHash.new("Button1"),
                    };
                    game_context.button_bindings[0] = button_binding;
                    var axis_binding = SdlControllerAxisBinding{
                        .target = StringHash.new("Axis1"),
                        .invert = false,
                        .deadzone = 0.2,
                        .sensitivity = 1.0,
                    };
                    game_context.axis_bindings[1] = axis_binding;

                    var context_bindings = std.AutoHashMap(StringHash.HashType, SdlControllerContext).init(self.allocator);
                    try context_bindings.put(GameInputContext.name.hash, game_context);

                    try self.controllers.put(sdl_event.cdevice.which, .{
                        .name = controller_name,
                        .handle = controller_handle,
                        .haptic = c.SDL_HapticOpen(sdl_event.cdevice.which),
                        .context_bindings = context_bindings,
                    });
                }
            },
            c.SDL_CONTROLLERDEVICEREMOVED => {
                if (self.controllers.fetchRemove(sdl_event.cdevice.which)) |*key_value| {
                    var controller = key_value.value;
                    log.info("Controller Removed Event: {}->{s}", .{ key_value.key, controller.name });
                    controller.deinit();
                }
            },
            c.SDL_CONTROLLERBUTTONDOWN, c.SDL_CONTROLLERBUTTONUP => {
                if (self.controllers.get(sdl_event.cbutton.which)) |controller| {
                    //log.info("Controller Event: {s}({}) button event: {}->{}", .{ controller.name, sdl_event.cbutton.which, sdl_event.cbutton.button, sdl_event.cbutton.state });
                    if (controller.get_button_binding(self.input_system.active_context.hash, sdl_event.cbutton.button)) |binding| {
                        self.input_system.trigger_button(binding.target, switch (sdl_event.cbutton.state) {
                            c.SDL_PRESSED => .Pressed,
                            c.SDL_RELEASED => .Released,
                            else => unreachable,
                        });
                    }
                }
            },
            c.SDL_CONTROLLERAXISMOTION => {
                if (self.controllers.get(sdl_event.caxis.which)) |controller| {
                    //log.info("Controller Event: {s}({}) axis event: {}->{}", .{ controller.name, sdl_event.caxis.which, sdl_event.caxis.axis, sdl_event.caxis.value });
                    if (controller.get_axis_binding(self.input_system.active_context.hash, sdl_event.caxis.axis)) |binding| {
                        var value = @intToFloat(f32, sdl_event.caxis.value) / @intToFloat(f32, c.SDL_JOYSTICK_AXIS_MAX);
                        self.input_system.trigger_axis(binding.target, std.math.clamp(binding.calc_value(value), -1.0, 1.0));
                    }
                }
            },
            else => {},
        }
    }
};

const InputStruct = struct {
    const Self = @This();

    some_int: usize,

    fn callback(self: *Self) InputContextCallback {
        return .{
            .ptr = self,
            .button_callback = trigger_button,
            .axis_callback = trigger_axis,
        };
    }

    fn trigger_button(self: *anyopaque, button: StringHash, state: ButtonState) void {
        _ = self;
        log.info("Button Triggered {s} -> {}", .{ button.string, state });
    }

    fn trigger_axis(self: *anyopaque, axis: StringHash, value: f32) void {
        _ = self;
        log.info("Axis Triggered {s} -> {d:.2}", .{ axis.string, value });
    }
};

const GameInputContext = InputContext{
    .name = StringHash.new("Game"),
    .buttons = &[_]StringHash{StringHash.new("Button1")},
    .axes = &[_]StringHash{StringHash.new("Axis1")},
};

pub fn main() !void {
    log.info("Info Logging", .{});
    log.warn("Warn Logging", .{});
    log.err("Error Logging", .{});
    log.debug("Debug Logging", .{});

    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (general_purpose_allocator.deinit() == true) {
        log.err("GeneralPurposeAllocator has a memory leak!", .{});
    };
    var allocator = general_purpose_allocator.allocator();

    log.info("Starting SDL2", .{});
    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_JOYSTICK | c.SDL_INIT_GAMECONTROLLER | c.SDL_INIT_HAPTIC) != 0) {
        log.err("{s}", .{c.SDL_GetError()});
        return;
    }
    defer {
        log.info("Shutting Down SDL2", .{});
        c.SDL_Quit();
    }

    var input_system = try InputSystem.init(
        allocator,
        &[_]InputContext{GameInputContext},
    );
    defer input_system.deinit();

    var sdl_input_system = SdlInputSystem.new(allocator, &input_system);
    defer sdl_input_system.deinit();

    var input_struct = InputStruct{
        .some_int = 0,
    };
    try input_system.add_callback(GameInputContext.name, input_struct.callback());

    var window = c.SDL_CreateWindow("Saturn", 0, 0, 1920, 1080, c.SDL_WINDOW_MAXIMIZED | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI);
    defer c.SDL_DestroyWindow(window);

    mainloop: while (true) {
        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event) != 0) {
            try sdl_input_system.proccess_event(&sdl_event);
            switch (sdl_event.type) {
                c.SDL_QUIT => break :mainloop,
                else => {},
            }
        }
    }
}

// Pong Engine Systems:
// 1. Windowing
// 2. Input (Keyboard + Mouse + Gamepad)
// 3. Audio
// 4. Graphics

// Pong Game Systems:
// 1. Gameplay (Paddle movement + Ball Physics)
// 2. Scoring System
// 3. UI (Start Menu + Pause Menu + Settings Menu + Score UI)
