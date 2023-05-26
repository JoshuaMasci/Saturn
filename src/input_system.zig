const std = @import("std");

// Input System Design
//  Inspired by https://www.gamedev.net/blogs/entry/2250186-designing-a-robust-input-handling-system-for-games/
//  Input Types:
//      1. Action - Button Pressed/Released
//      2. State - Button Up/Down
//      3. Range - Joystick Position / Mouse Movement
//
//  Input Context:
//      A context is a list of named inputs and callbacks
//      Contexts can be enabled or disabled at runtime
//      Contexts and Input names should all be comptime known
//
//  Input Device:
//      An input device is a device that can trigger an input
//
//  Event Flow:
//  SDL2 -> InputSystem -> BindingMapping -> Context -> ContextCallback

pub const TestInputContext = struct {
    const Actions = enum {
        OpenMenu,
        SwingSword,
        Jump,
    };
    const States = enum {
        Sprinting,
        Crouching,
        AimingDownSights,
    };
    const Ranges = enum {
        WalkFoward,
        WalkStrife,
        LookVertical,
        LookHorizontal,
    };
};

// fn GetEnumNameValue(comptime T: type) void {
//     comptime var type_name = @typeName(T);
//     comptime var type_info = @typeInfo(T);
//     log.info("{s}:", .{type_name});
//     inline for (type_info.Enum.fields) |value| {
//         log.info("  {s}: {}", .{ value.name, value.value });
//     }
// }
//comptime StateTypes: type, comptime RangeTypes: type
// const TestInputContext = input.InputContext(TestEnum);
// log.info("TestInputContext:", .{});
// inline for (TestInputContext.get_actions()) |action| {
//     log.info("   {s}: {}", .{ action.name, action.value });
// }
// var input_context = TestInputContext.new(null, null);
// _ = input_context;
pub const ButtonState = enum {
    Pressed,
    Released,
};

pub fn InputContext(
    comptime ButtonType: type,
) type {
    comptime var button_type_info = @typeInfo(ButtonType);

    return struct {
        const Self = @This();

        const ButtonCallback = ?*fn (data: *anyopaque, button: ButtonType, state: ButtonState) void;

        callback_data: *anyopaque,
        button_callback: ButtonCallback,

        pub fn new(
            callback_data: *anyopaque,
            button_callback: ButtonCallback,
        ) Self {
            return .{
                .callback_data = callback_data,
                .button_callback = button_callback,
            };
        }

        pub fn get_buttons() []const std.builtin.Type.EnumField {
            return button_type_info.Enum.fields;
        }
    };
}

pub const InputSystem = struct {
    const Self = @This();

    pub fn new() Self {
        return .{};
    }
    pub fn deinit(self: Self) void {
        _ = self;
    }

    fn addContext(self: Self, comptime T: type, context: T) void {
        _ = self;
        _ = context;
    }
};
