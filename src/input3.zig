const std = @import("std");

//TODO: held and released should contain time down/up
pub const ButtonState = enum {
    released,
    pressed,
    held,

    pub fn isDown(self: @This()) bool {
        return self == .pressed or self == .held;
    }
};

pub const DeviceButtonState = struct {
    timestamp: u64 = 0,
    state: ButtonState = .released,
};

pub const DeviceAxisState = struct {
    timestamp: u64 = 0,
    value: f32 = 0.0,
};

pub const InputDevice = struct {
    const Self = @This();

    ptr: *anyopaque,
    get_button_state: *const fn (ptr: *anyopaque, context_hash: u32, button: u32) ?DeviceButtonState,
    get_axis_state: *const fn (ptr: *anyopaque, context_hash: u32, axis: u32) ?DeviceAxisState,

    pub fn getButton(self: Self, context_hash: u32, button: u32) ?DeviceButtonState {
        return self.get_button_state(self.ptr, context_hash, button);
    }

    pub fn getAxis(self: Self, context_hash: u32, axis: u32) ?DeviceAxisState {
        return self.get_axis_state(self.ptr, context_hash, axis);
    }
};

pub const InputContextDefinition = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    name_hash: u32,
    button_names: [][]const u8,
    axis_names: [][]const u8,

    pub fn deinit(self: *InputContextDefinition) void {
        for (self.button_names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.button_names);

        for (self.axis_names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.axis_names);
        self.allocator.free(self.name);
    }
};

pub fn InputContext(
    comptime name: []const u8,
    comptime ButtonEnum: type,
    comptime AxisEnum: type,
) type {
    const name_hash = std.hash.Fnv1a_32.hash(name);

    return struct {
        const Self = @This();

        button_states: std.EnumArray(ButtonEnum, DeviceButtonState),
        axis_states: std.EnumArray(AxisEnum, DeviceAxisState),

        pub fn init(devices: []const InputDevice) Self {
            var self: Self =
                .{
                .button_states = std.EnumArray(ButtonEnum, DeviceButtonState).initFill(.{}),
                .axis_states = std.EnumArray(AxisEnum, DeviceAxisState).initFill(.{}),
            };
            self.update(devices);
            return self;
        }

        fn update(self: *Self, devices: []const InputDevice) void {
            // Update button states
            inline for (std.meta.fields(ButtonEnum)) |field| {
                const button_enum = @field(ButtonEnum, field.name);
                const button_index = @intFromEnum(button_enum);

                var state: DeviceButtonState = .{};

                for (devices) |device| {
                    if (device.getButton(name_hash, button_index)) |button_state| {
                        if (button_state.state == .held) {
                            state.state = .held;
                            state.timestamp = @max(state.timestamp, button_state.timestamp);
                        } else if (button_state.state == .pressed and state.state != .held) {
                            state = button_state;
                        }
                    }
                }

                self.button_states.set(button_enum, state);
            }

            // Update axis states
            inline for (std.meta.fields(AxisEnum)) |field| {
                const axis_enum = @field(AxisEnum, field.name);
                const axis_index = @intFromEnum(axis_enum);

                var state: DeviceAxisState = .{};

                for (devices) |device| {
                    if (device.getAxis(name_hash, axis_index)) |axis_state| {
                        if (axis_state.timestamp >= state.timestamp) {
                            state = axis_state;
                        }
                    }
                }

                self.axis_states.set(axis_enum, state);
            }
        }

        pub fn getButtonDown(self: Self, button: ButtonEnum) bool {
            const state = self.button_states.get(button);
            return state.state == .pressed or state.state == .down;
        }

        pub fn getButtonPressed(self: Self, button: ButtonEnum) bool {
            const state = self.button_states.get(button);
            return state.state == .pressed;
        }

        pub fn getAxisValue(self: Self, axis: AxisEnum, clamp: bool) f32 {
            var value = self.axis_states.get(axis).value;
            if (clamp) {
                value = std.math.clamp(value, -1, 1);
            }
            return value;
        }

        pub fn getButtonAxis(self: Self, axis: AxisEnum, pos: ButtonEnum, neg: ButtonEnum, clamp: bool) f32 {
            const axis_state = self.getAxisValue(axis, clamp);
            const pos_state = self.getButtonDown(pos);
            const neg_state = self.getButtonDown(neg);

            if (pos_state and !neg_state) {
                return 1.0;
            } else if (neg_state and !pos_state) {
                return -1.0;
            } else if (pos_state and neg_state) {
                return 0.0;
            } else {
                return axis_state;
            }
        }

        pub fn getDefinition(allocator: std.mem.Allocator) !InputContextDefinition {
            // Duplicate name string
            const name_copy = try allocator.dupe(u8, name);
            errdefer allocator.free(name_copy);

            // Create button names array
            const button_fields = std.meta.fields(ButtonEnum);
            var button_names = try allocator.alloc([]const u8, button_fields.len);
            errdefer allocator.free(button_names);

            // Fill button names
            var button_success: usize = 0;
            errdefer {
                for (button_names[0..button_success]) |button_name| {
                    allocator.free(button_name);
                }
            }

            for (button_fields, 0..) |field, i| {
                button_names[i] = try allocator.dupe(u8, field.name);
                button_success += 1;
            }

            // Create axis names array
            const axis_fields = std.meta.fields(AxisEnum);
            var axis_names = try allocator.alloc([]const u8, axis_fields.len);
            errdefer allocator.free(axis_names);

            // Fill axis names
            var axis_success: usize = 0;
            errdefer {
                for (axis_names[0..axis_success]) |axis_name| {
                    allocator.free(axis_name);
                }
            }

            for (axis_fields, 0..) |field, i| {
                axis_names[i] = try allocator.dupe(u8, field.name);
                axis_success += 1;
            }

            return InputContextDefinition{
                .allocator = allocator,
                .name = name_copy,
                .name_hash = name_hash,
                .button_names = button_names,
                .axis_names = axis_names,
            };
        }
    };
}
