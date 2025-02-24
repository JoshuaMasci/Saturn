const std = @import("std");
const StringHash = @import("string_hash.zig");

pub const InputContextDefinition = struct {
    name: StringHash,
    buttons: []const StringHash,
    axes: []const StringHash,
};

const ButtonState = struct {
    current: bool = false,
    previous: bool = false,
};

pub const InputContext = struct {
    const Self = @This();

    const Button = struct {
        name: StringHash,
        current: bool = false,
        previous: bool = false,
    };

    const Axis = struct {
        name: StringHash,
        current: f32,
    };

    definition: *const InputContextDefinition,

    buttons: std.AutoArrayHashMap(StringHash.HashType, Button),
    axes: std.AutoArrayHashMap(StringHash.HashType, Axis),

    pub fn deinit(self: *Self) void {
        self.buttons.deinit();
        self.axes.deinit();
    }

    pub fn isButtonDown(self: *Self, button: StringHash) bool {
        return self.buttons.get(button.hash).?.current;
    }
    pub fn isButtonPressed(self: *Self, button: StringHash) bool {
        const button_state = self.buttons.get(button.hash).?;
        return button_state.current and !button_state.previous;
    }

    pub fn getAxisValue(self: *Self, axis: StringHash, clamp: bool) f32 {
        var value = self.axes.get(axis.hash).?.current;
        if (clamp) {
            value = std.math.clamp(value, -1.0, 1.0);
        }
        return value;
    }
};

pub const InputDevice = struct {
    const Self = @This();

    ptr: *anyopaque,
    get_button: *fn (ptr: *anyopaque, context: StringHash, button: StringHash) ?bool,
    get_axis: *fn (ptr: *anyopaque, context: StringHash, axis: StringHash) ?f32,

    pub fn getButton(self: Self, context: StringHash, button: StringHash) ?bool {
        return self.get_button(self.ptr, context, button);
    }

    pub fn getAxis(self: Self, context: StringHash, axis: StringHash) ?f32 {
        return self.get_axis(self.ptr, context, axis);
    }
};

pub const InputSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    devices: std.AutoArrayHashMap(*anyopaque, InputDevice),
    contexts: std.AutoArrayHashMap(StringHash.HashType, *InputContext),

    active_context: ?StringHash.HashType = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .devices = std.AutoArrayHashMap(*anyopaque, InputDevice).init(allocator),
            .contexts = std.AutoArrayHashMap(StringHash.HashType, *InputContext).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.devices.deinit();

        for (self.contexts.values()) |context| {
            context.deinit();
            self.allocator.destroy(context);
        }
        self.contexts.deinit();
    }

    pub fn addDevice(self: *Self, device: InputDevice) !void {
        try self.devices.put(device.ptr, device);
    }

    pub fn removeDevice(self: *Self, device_ptr: *anyopaque) void {
        _ = self.devices.swapRemove(device_ptr);
    }

    pub fn createContext(self: *Self, context: InputContextDefinition) !void {
        _ = self; // autofix
        _ = context; // autofix
    }

    pub fn enableContext(self: *Self, context_name: StringHash) void {
        if (self.contexts.contains(context_name.hash)) {
            self.active_context = context_name.hash;
        }
    }

    pub fn update(self: *Self) void {
        if (self.active_context) |context_hash| {
            if (self.contexts.get(context_hash)) |active_context| {

                //Update Button Values
                for (active_context.buttons.values()) |*button| {
                    button.previous = button.current;
                    button.current = false;

                    for (self.devices.values()) |device| {
                        button.current = button.current or device.getButton(active_context.definition.name, button.name).?;
                    }
                }

                //Update Axis Values
                for (active_context.axes.values()) |*axis| {
                    for (self.devices.values()) |device| {
                        //TODO: only set most recent value
                        axis.current = device.getAxis(active_context.definition.name, axis.name).?;
                    }
                }
            }
        }
    }

    pub fn getContext(self: *Self, context_name: StringHash) ?*InputContext {
        if (self.active_context == context_name.hash) {
            return self.contexts.get(context_name.hash);
        }
        return null;
    }

    pub fn getActiveDevice(self: Self) void {
        _ = self; // autofix
    }

    pub fn getTextInput(self: Self) ?[]const u8 {
        _ = self; // autofix
        return null;
    }
};
