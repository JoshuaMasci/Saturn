const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

const std = @import("std");
const panic = std.debug.panic;

const ArrayList = std.ArrayList;

const GeneralPurposeAllocator: type = std.heap.GeneralPurposeAllocator(.{});

fn glfwErrorCallback(err: c_int, description: [*c]const u8) callconv(.C) void {
    panic("Error: {s}\n", .{@as([*:0]const u8, description)});
}

fn glfwMouseCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (action == c.GLFW_PRESS) {
        input.setMouseState(@intCast(usize, button), true);
    }
    else if (action == c.GLFW_RELEASE) {
        input.setMouseState(@intCast(usize, button), false);
    }
}

fn glfwKeyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (action == c.GLFW_PRESS) {
        input.setKeyState(@intCast(usize, key), true);
    }
    else if (action == c.GLFW_RELEASE) {
        input.setKeyState(@intCast(usize, key), false);
    }
}

fn glfwMouseMoveCallback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
    if (window == capturedWindow) {
        input.mouse_axes[0] = @floatCast(f32, xpos);
        input.mouse_axes[1] = @floatCast(f32, ypos);
    }
    else {
        // Set mouse pos
    }
}

fn glfwMouseEnteredCallback(window: ?*c.GLFWwindow, entered: c_int) callconv(.C) void {
    //If mouse has left current capture area
    var focused = c.glfwGetWindowAttrib(window, c.GLFW_FOCUSED);
    if (capturedWindow == window and entered == 0 and focused == 0) {
        c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
        capturedWindow = null;
    }
}

//Global Variables/Functions
var globalAllocator: GeneralPurposeAllocator = undefined;

pub fn init() void {
    globalAllocator = GeneralPurposeAllocator{};
    windowMap = WindowHashMap.init(&globalAllocator.allocator);

    _ = c.glfwSetErrorCallback(glfwErrorCallback);
    if (c.glfwInit() == c.GL_FALSE) {
        panic("Failed to initialise glfw\n", .{});
    }

    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GL_TRUE);
}

pub fn deinit() void {
    c.glfwTerminate();
    windowMap.deinit();
    const leaked = globalAllocator.deinit();
    if (leaked) panic("Error: memory leaked", .{});
}

pub fn update() void {
     if (capturedWindow) |windowHandle| {
        c.glfwSetCursorPos(windowHandle, 0.0, 0.0);
     }

    input.update();
    c.glfwPollEvents();
}

pub fn getTime() f64 {
    return c.glfwGetTime();
}

//Window Variables/Functions
pub const WindowId = usize;
const WindowHashMap = std.AutoHashMap(WindowId, *c.GLFWwindow);
var nextWindowId: WindowId = 0;
var windowMap: WindowHashMap = undefined;
pub fn createWindow(width: i32, height: i32, title: [:0]const u8) WindowId {
    var handle = c.glfwCreateWindow(width, height, title, null, null) orelse {
        panic("Failed to create window", .{});
    };
    c.glfwMakeContextCurrent(handle);
    _ = c.glfwSetMouseButtonCallback(handle, glfwMouseCallback);
    _ = c.glfwSetKeyCallback(handle, glfwKeyCallback);
    _ = c.glfwSetCursorPosCallback(handle, glfwMouseMoveCallback);
    _ = c.glfwSetCursorEnterCallback(handle, glfwMouseEnteredCallback);

    windowMap.put(nextWindowId, handle) catch panic("Failed to add window Id", .{});
    var windowId = nextWindowId;
    nextWindowId += 1;
    return windowId;
}

pub fn destoryWindow(windowId: WindowId) void {
    if (windowMap.contains(windowId)) {
        var handle = windowMap.remove(windowId).?.value;
        c.glfwDestroyWindow(handle);
    }
}

pub fn refreshWindow(windowId: WindowId) void {
    if (windowMap.contains(windowId)) {
        c.glfwSwapBuffers(windowMap.get(windowId).?);
    }
}

pub fn shouldCloseWindow(windowId: WindowId) bool {
    if (windowMap.contains(windowId)) {
        return c.glfwWindowShouldClose(windowMap.get(windowId).?) == 0;
    }
    return false;
}

pub fn getWindowSize(windowId: WindowId) [2]i32 {
    var size: [2]i32 = undefined;
    if (windowMap.contains(windowId)) {
        var cSize: [2]c_int = undefined;
        c.glfwGetFramebufferSize(windowMap.get(windowId).?, &cSize[0], &cSize[1]);
        size[0] = @intCast(i32, cSize[0]);
        size[1] = @intCast(i32, cSize[1]);
    }
    return size;
}

pub fn maximizeWindow(windowId: WindowId) void {
    if (windowMap.contains(windowId)) {
        c.glfwMaximizeWindow(getWindowHandle(windowId));
    }
}

pub fn getWindowHandle(windowId: WindowId) *c.GLFWwindow {
    if (windowMap.contains(windowId)) {
        return windowMap.get(windowId).?;
    }
    panic("Tried to get handle for invalid window", .{});
}

pub fn isWindowHovered(windowId: WindowId) bool {
    if (windowMap.contains(windowId)) {
        return c.glfwGetWindowAttrib(getWindowHandle(windowId), c.GLFW_HOVERED) != 0;
    }
    return false;
}

pub fn isWindowFocused(windowId: WindowId) bool {
    if (windowMap.contains(windowId)) {
        return c.glfwGetWindowAttrib(getWindowHandle(windowId), c.GLFW_FOCUSED) != 0;
    }
    return false;
}

pub fn setMouseCaptured(windowId: WindowId, capture: bool) void {
    if (windowMap.contains(windowId)) {
        var handle = getWindowHandle(windowId);
        if (capture) {
            c.glfwSetInputMode(handle, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
            c.glfwSetCursorPos(handle, 0.0, 0.0);
            capturedWindow = handle;
        }
        else {
            var size = getWindowSize(windowId);
            c.glfwSetInputMode(handle, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
            c.glfwSetCursorPos(handle, @intToFloat(f64, size[0]) / 2.0,  @intToFloat(f64, size[1]) / 2.0);
            capturedWindow = null;
        }
    }
}

pub fn getMouseCaptured(windowId: WindowId) bool {
    if (capturedWindow) |windowHandle| {
        return true;
    }
    else {
        return false;
    }
}

var capturedWindow: ?*c.GLFWwindow = null;

//Input Variables/Functions
const MouseButtonCount: usize = c.GLFW_MOUSE_BUTTON_LAST;
const KeyboardButtonCount: usize = c.GLFW_KEY_LAST;

const ButtonInput = struct {
    current_state: bool = false,
    prev_state: bool = false,
};

pub var input = struct {
    const Self = @This();

    mouse_buttons: [MouseButtonCount]ButtonInput,
    keyboard_buttons: [KeyboardButtonCount]ButtonInput,
    mouse_axes: [2]f32,

    pub fn init() Self {
        return Self {
            .mouse_buttons = [_]ButtonInput{.{}} ** MouseButtonCount,
            .keyboard_buttons = [_]ButtonInput{.{}} ** KeyboardButtonCount,
            .mouse_axes = [_]f32{ 0.0, 0.0 },
        };
    }

    pub fn update(self: *Self) void {
        for (self.mouse_buttons) |*button| {
            button.prev_state = button.current_state;
        }

        for (self.keyboard_buttons) |*button| {
            button.prev_state = button.current_state;
        }

        self.mouse_axes = [_]f32{ 0.0, 0.0 };
    }

    pub fn setMouseState(self: *Self, mouse_button: usize, state: bool) void {
        self.mouse_buttons[mouse_button].current_state = state;
    }

    pub fn getMouseDown(self: *Self, mouse_button: usize) bool {
        return self.mouse_buttons[mouse_button].current_state == true;
    }

    pub fn getMousePressed(self: *Self, mouse_button: usize) bool {
        var button = self.mouse_buttons[mouse_button];
        return button.current_state == true and button.prev_state == false;
    }

    pub fn getMouseAxes(self: *Self) [2]f32 {
        return self.mouse_axes;
    }


    pub fn setKeyState(self: *Self, key: usize, state: bool) void {
        self.keyboard_buttons[key].current_state = state;
    }

    pub fn getKeyDown(self: *Self, key: usize) bool {
        return self.keyboard_buttons[key].current_state == true;
    }

    pub fn getKeyPressed(self: *Self, key: usize) bool {
        var button = self.keyboard_buttons[key];
        return button.current_state == true and button.prev_state == false;
    }
}.init();