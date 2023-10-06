const std = @import("std");
const StringHash = @import("string_hash.zig");
const input = @import("input.zig");
const sdl = @import("zsdl");

pub const SdlButtonBinding = struct {
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
pub fn DeviceContextBinding(comptime ButtonBinding: type, comptime ButtonCount: comptime_int, comptime AxisBinding: type, comptime AxisCount: comptime_int) type {
    return struct {
        const Self = @This();

        button_bindings: [ButtonCount]?ButtonBinding,
        axis_bindings: [AxisCount]?AxisBinding,

        pub fn default() @This() {
            return .{
                .button_bindings = [_]?ButtonBinding{null} ** ButtonCount,
                .axis_bindings = [_]?AxisBinding{null} ** AxisCount,
            };
        }

        pub fn get_button_binding(self: Self, index: usize) ?ButtonBinding {
            return self.button_bindings[index];
        }

        pub fn get_axis_binding(self: Self, index: usize) ?AxisBinding {
            return self.axis_bindings[index];
        }
    };
}

pub const SdlControllerMaxButtons: u32 = @intFromEnum(sdl.GameController.Button.touchpad);
pub const SdlControllerMaxAxis: u32 = @intFromEnum(sdl.GameController.Axis.triggerright);

pub const SdlControllerContextBinding = DeviceContextBinding(SdlButtonBinding, SdlControllerMaxButtons, SdlControllerAxisBinding, SdlControllerMaxAxis);
pub const SdlController = struct {
    const Self = @This();

    name: [*c]const u8,
    handle: *sdl.GameController,
    //haptic: ?*sdl.Haptic,

    context_bindings: std.AutoHashMap(StringHash.HashType, SdlControllerContextBinding),

    pub fn deinit(self: *Self) void {
        // if (self.haptic) |haptic| {
        //     c.SDL_HapticClose(haptic);
        // }
        self.handle.close();
        self.context_bindings.deinit();
    }

    pub fn get_button_binding(self: Self, context_hash: StringHash.HashType, index: usize) ?SdlButtonBinding {
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

pub const MaxScancodes: u32 = @intFromEnum(sdl.Scancode.endcall);

pub const SdlKeyboardContextBinding = DeviceContextBinding(SdlButtonBinding, MaxScancodes, void, 0);
pub const SdlKeyboard = struct {
    const Self = @This();

    context_bindings: std.AutoHashMap(StringHash.HashType, SdlKeyboardContextBinding),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .context_bindings = std.AutoHashMap(StringHash.HashType, SdlKeyboardContextBinding).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.context_bindings.deinit();
    }

    pub fn get_button_binding(self: Self, context_hash: StringHash.HashType, index: usize) ?SdlButtonBinding {
        if (self.context_bindings.getPtr(context_hash)) |context| {
            return context.get_button_binding(index);
        }
        return null;
    }
};

pub const SdlInputSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    input_system: *input.InputSystem,

    keyboard: ?SdlKeyboard,
    mouse: struct {},
    controllers: std.AutoHashMap(sdl.JoystickId, SdlController),

    pub fn new(
        allocator: std.mem.Allocator,
        input_system: *input.InputSystem,
    ) Self {
        return .{
            .allocator = allocator,
            .input_system = input_system,
            .keyboard = SdlKeyboard.init(allocator),
            .mouse = .{},
            .controllers = std.AutoHashMap(sdl.JoystickId, SdlController).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.controllers.iterator();
        while (iterator.next()) |controller| {
            controller.value_ptr.deinit();
        }
        self.controllers.deinit();

        if (self.keyboard) |*keyboard| {
            keyboard.deinit();
        }
    }

    pub fn proccess_event(self: *Self, sdl_event: *sdl.Event) !void {
        _ = self;
        _ = sdl_event;
        // switch (sdl_event.type) {
        //     c.SDL_CONTROLLERDEVICEADDED => {
        //         var controller_result: ?*c.SDL_GameController = c.SDL_GameControllerOpen(sdl_event.cdevice.which);
        //         if (controller_result) |controller_handle| {
        //             var controller_name = c.SDL_GameControllerName(controller_handle);
        //             log.info("Controller Added Event: {}->{s}", .{ sdl_event.cdevice.which, controller_name });

        //             var context_bindings = std.AutoHashMap(StringHash.HashType, SdlControllerContextBinding).init(self.allocator);

        //             //TODO: load or generate bindings
        //             var game_context = SdlControllerContextBinding.default();
        //             var button_binding = SdlButtonBinding{
        //                 .target = StringHash.new("Button1"),
        //             };
        //             game_context.button_bindings[0] = button_binding;
        //             var axis_binding = SdlControllerAxisBinding{
        //                 .target = StringHash.new("Axis1"),
        //                 .invert = false,
        //                 .deadzone = 0.2,
        //                 .sensitivity = 1.0,
        //             };
        //             game_context.axis_bindings[1] = axis_binding;

        //             //Temp Hack
        //             const GameInputContext = @import("app.zig").GameInputContext;

        //             try context_bindings.put(GameInputContext.name.hash, game_context);
        //             try self.controllers.put(sdl_event.cdevice.which, .{
        //                 .name = controller_name,
        //                 .handle = controller_handle,
        //                 .haptic = c.SDL_HapticOpen(sdl_event.cdevice.which),
        //                 .context_bindings = context_bindings,
        //             });
        //         }
        //     },
        //     c.SDL_CONTROLLERDEVICEREMOVED => {
        //         if (self.controllers.fetchRemove(sdl_event.cdevice.which)) |*key_value| {
        //             var controller = key_value.value;
        //             log.info("Controller Removed Event: {}->{s}", .{ key_value.key, controller.name });
        //             controller.deinit();
        //         }
        //     },
        //     c.SDL_CONTROLLERBUTTONDOWN, c.SDL_CONTROLLERBUTTONUP => {
        //         if (self.controllers.get(sdl_event.cbutton.which)) |controller| {
        //             //log.info("Controller Event: {s}({}) button event: {}->{}", .{ controller.name, sdl_event.cbutton.which, sdl_event.cbutton.button, sdl_event.cbutton.state });
        //             if (controller.get_button_binding(self.input_system.active_context.hash, sdl_event.cbutton.button)) |binding| {
        //                 self.input_system.trigger_button(binding.target, switch (sdl_event.cbutton.state) {
        //                     c.SDL_PRESSED => .Pressed,
        //                     c.SDL_RELEASED => .Released,
        //                     else => unreachable,
        //                 });
        //             }
        //         }
        //     },
        //     c.SDL_CONTROLLERAXISMOTION => {
        //         if (self.controllers.get(sdl_event.caxis.which)) |controller| {
        //             //log.info("Controller Event: {s}({}) axis event: {}->{}", .{ controller.name, sdl_event.caxis.which, sdl_event.caxis.axis, sdl_event.caxis.value });
        //             if (controller.get_axis_binding(self.input_system.active_context.hash, sdl_event.caxis.axis)) |binding| {
        //                 var value = @as(f32, @floatFromInt(sdl_event.caxis.value)) / @as(f32, @floatFromInt(c.SDL_JOYSTICK_AXIS_MAX));
        //                 self.input_system.trigger_axis(binding.target, std.math.clamp(binding.calc_value(value), -1.0, 1.0));
        //             }
        //         }
        //     },
        //     c.SDL_KEYDOWN, c.SDL_KEYUP => {
        //         //No repeat events for keyboard buttons, text input should have repeat events tho
        //         if (sdl_event.key.repeat == 0) {
        //             //log.info("Keyboard Event {}->{}", .{ sdl_event.key.keysym.scancode, sdl_event.key.state });
        //             if (self.keyboard) |keyboard| {
        //                 if (keyboard.get_button_binding(self.input_system.active_context.hash, sdl_event.key.keysym.scancode)) |binding| {
        //                     self.input_system.trigger_button(binding.target, switch (sdl_event.key.state) {
        //                         c.SDL_PRESSED => .Pressed,
        //                         c.SDL_RELEASED => .Released,
        //                         else => unreachable,
        //                     });
        //                 }
        //             }
        //         }
        //     },
        //     else => {},
        // }
    }
};
