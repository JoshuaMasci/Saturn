const std = @import("std");
const StringHash = @import("string_hash.zig");

pub const ButtonState = enum {
    Pressed,
    Released,
};

pub const InputContext = struct {
    name: StringHash,
    buttons: []const StringHash,
    axes: []const StringHash,
};

pub const InputButtonCallback = *const fn (ptr: *anyopaque, button: StringHash, state: ButtonState) void;
pub const InputAxisCallback = *const fn (ptr: *anyopaque, axis: StringHash, value: f32) void;

pub const InputContextCallback = struct {
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

pub const InputSystem = struct {
    const Self = @This();

    const InnerContext = struct {
        context: InputContext,
        callbacks: std.ArrayList(InputContextCallback),
    };
    context_map: std.AutoHashMap(StringHash.HashType, InnerContext),
    active_context: StringHash,

    pub fn init(allocator: std.mem.Allocator, contexts: []const InputContext) !Self {
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

    pub fn deinit(self: *Self) void {
        var iterator = self.context_map.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.callbacks.deinit();
        }
        self.context_map.deinit();
    }

    pub fn add_callback(self: *Self, context_name: StringHash, callback: InputContextCallback) !void {
        if (self.context_map.getPtr(context_name.hash)) |inner_context| {
            try inner_context.callbacks.append(callback);
        }
    }

    pub fn set_active_context(self: *Self, context_name: StringHash) void {
        if (self.context_map.contains(context_name.hash)) {
            self.active_context = context_name;
        } else {
            unreachable;
        }
    }

    pub fn trigger_button(self: *Self, button: StringHash, state: ButtonState) void {
        if (self.context_map.getPtr(self.active_context.hash)) |context| {
            for (context.callbacks.items) |callback| {
                //TODO: verify that button is part of context
                callback.trigger_button(button, state);
            }
        } else {
            unreachable;
        }
    }

    pub fn trigger_axis(self: *Self, axis: StringHash, value: f32) void {
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
