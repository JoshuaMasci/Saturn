usingnamespace @import("core.zig");
const panic = std.debug.panic;

const glfw = @import("glfw");

const MouseButtonCount: usize = @enumToInt(glfw.mouse_button.last);
const KeyboardButtonCount: usize = @enumToInt(glfw.Key.last());
pub const TextInput = std.ArrayList(u16);

const ButtonInput = struct {
    current_state: bool = false,
    prev_state: bool = false,
};

fn key_callback(window: glfw.Window, key: glfw.Key, scancode: isize, action: glfw.Action, mods: glfw.Mods) void {
    _ = scancode;
    _ = mods;
    var internal_result = window.getUserPointer(*InputData);
    if (internal_result) |internal| {
        if (key != glfw.Key.unknown) {
            var key_int = @intCast(usize, @enumToInt(key));
            if (action == glfw.Action.press) {
                internal.keyboard_buttons[key_int].current_state = true;
            } else if (action == glfw.Action.release) {
                internal.keyboard_buttons[key_int].current_state = false;
            }
        }
    }
}

fn mouse_button_callback(window: glfw.Window, button: glfw.mouse_button.MouseButton, action: glfw.Action, mods: glfw.Mods) void {
    _ = mods;
    var internal_result = window.getUserPointer(*InputData);
    if (internal_result) |internal| {
        var button_int = @intCast(usize, @enumToInt(button));
        if (action == glfw.Action.press) {
            internal.mouse_buttons[button_int].current_state = true;
        } else if (action == glfw.Action.release) {
            internal.mouse_buttons[button_int].current_state = false;
        }
    }
}

fn mouse_move_button(window: glfw.Window, xpos: f64, ypos: f64) void {
    var internal_result = window.getUserPointer(*InputData);
    if (internal_result) |internal| {
        internal.mouse_pos = [2]f32{ @floatCast(f32, xpos), @floatCast(f32, ypos) };
    }
}

fn mouse_entered(window: glfw.Window, entered: bool) void {
    var internal_result = window.getUserPointer(*InputData);
    if (internal_result) |internal| {
        if (!entered) {
            internal.mouse_pos = null;
        }
    }
}

fn text_entered(window: glfw.Window, character_u21: u21) void {
    var internal_result = window.getUserPointer(*InputData);
    if (internal_result) |internal| {
        var character = @intCast(u16, character_u21);
        internal.text_input.append(character) catch {
            panic("Failed to append text_input!", .{});
        };
    }
}

const InputData = struct {
    mouse_buttons: [MouseButtonCount]ButtonInput = [_]ButtonInput{.{}} ** MouseButtonCount,
    keyboard_buttons: [KeyboardButtonCount]ButtonInput = [_]ButtonInput{.{}} ** KeyboardButtonCount,
    mouse_pos: ?[2]f32 = null,
    text_input: TextInput,
};

pub const Input = struct {
    const Self = @This();

    allocator: *Allocator,
    window: glfw.Window,
    internal: *InputData,

    pub fn init(window: glfw.Window, allocator: *Allocator) !Self {
        var internal = try allocator.create(InputData);
        internal.text_input = TextInput.init(allocator);
        window.setUserPointer(*InputData, internal);

        window.setKeyCallback(key_callback);
        window.setMouseButtonCallback(mouse_button_callback);
        window.setCursorPosCallback(mouse_move_button);
        window.setCursorEnterCallback(mouse_entered);
        window.setCharCallback(text_entered);

        return Self{
            .allocator = allocator,
            .window = window,
            .internal = internal,
        };
    }

    pub fn deinit(self: *Self) void {
        self.window.setKeyCallback(null);
        self.window.setMouseButtonCallback(null);
        self.window.setCursorPosCallback(null);
        self.window.setCursorEnterCallback(null);

        //Clear Window User Pointer
        var internal = self.window.getInternal();
        internal.user_pointer = null;
        self.internal.text_input.deinit();
        self.allocator.destroy(self.internal);
    }

    pub fn update(self: *Self) void {
        for (self.internal.mouse_buttons) |*button| {
            button.prev_state = button.current_state;
        }

        for (self.internal.keyboard_buttons) |*button| {
            button.prev_state = button.current_state;
        }
    }

    pub fn getMouseDown(self: *Self, mouse_button: glfw.mouse_button.MouseButton) bool {
        var button_int = @intCast(usize, @enumToInt(mouse_button));
        return self.internal.mouse_buttons[button_int].current_state == true;
    }

    pub fn getMousePressed(self: *Self, mouse_button: glfw.mouse_button.MouseButton) bool {
        var button_int = @intCast(usize, @enumToInt(mouse_button));
        var button = self.internal.mouse_buttons[button_int];
        return button.current_state == true and button.prev_state == false;
    }

    pub fn getMousePos(self: *Self) ?[2]f32 {
        return self.internal.mouse_pos;
    }

    pub fn getKeyDown(self: *Self, key: glfw.Key) bool {
        var key_int = @intCast(usize, @enumToInt(key));
        return self.internal.keyboard_buttons[key_int].current_state == true;
    }

    pub fn getKeyPressed(self: *Self, key: glfw.Key) bool {
        var key_int = @intCast(usize, @enumToInt(key));
        var button = self.internal.keyboard_buttons[key_int];
        return button.current_state == true and button.prev_state == false;
    }

    pub fn getAndClearTextInput(self: *Self) TextInput {
        var temp = self.internal.text_input;
        self.internal.text_input = TextInput.init(self.allocator);
        return temp;
    }
};
