const std = @import("std");
const log = std.log;

const c = @import("c.zig");

const StringHash = @import("string_hash.zig");
const input = @import("input.zig");
const sdl_input = @import("sdl_input.zig");
const App = @import("app.zig").App;

const InputStruct = struct {
    const Self = @This();

    some_int: usize,

    fn callback(self: *Self) input.InputContextCallback {
        return .{
            .ptr = self,
            .button_callback = trigger_button,
            .axis_callback = trigger_axis,
        };
    }

    fn trigger_button(self: *anyopaque, button: StringHash, state: input.ButtonState) void {
        _ = self;
        log.info("Button Triggered {s} -> {}", .{ button.string, state });
    }

    fn trigger_axis(self: *anyopaque, axis: StringHash, value: f32) void {
        _ = self;
        log.info("Axis Triggered {s} -> {d:.2}", .{ axis.string, value });
    }
};

pub const GameInputContext = input.InputContext{
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
    defer if (general_purpose_allocator.deinit() == .leak) {
        log.err("GeneralPurposeAllocator has a memory leak!", .{});
    };
    var allocator = general_purpose_allocator.allocator();

    var app = try App.init(allocator);
    while (app.is_running()) {
        try app.update();
    }
    app.deinit();
}

//Pong Game:
//
//  Game Scenes:
//      Main Menu Scene
//      1. Start -> Opens the floating game start menu
//      2. Settings -> Opens the floating settings menu
//      3. Quit -> Quits the game
//      4. Background image of blurry pong game
//
//      Floating Game Start Menu
//      1. A.I. difficutly slider/option
//      2. Winning score slider/option
//      3. Start match button -> Tranitions to game scene
//      4. Some kind of back button that return to the previous screen
//
//      Floating Settings Menu
//      1. Gameplay ->
//      2. Audio -> Audio sliders for Master, Sfx, Music channels,
//      3. Keyboard -> Allows the remapping of keyboard bindings
//      4. Mouse -> Allows the remapping of mouse bindings
//      5. Controller(s) -> Allows the remapping of controller bindings for a given controller + haptic settings
//      6. Some kind of back button that return to the previous screen
//
//      Game Scene
//      1. Blue Player controlled paddle
//      2. Red A.i, controlled paddle
//      3. Pong Ball
//      4. Walls surrounding play area
//      5. Dotted light though center of play area
//      6. Text displaying current score
//      7. Background texture
//      8. Pressing ECS or <MENU> -> Pauses Game + Opens floating pause game menu
//      9. When winning score is reached -> Pauses Game + Open floating end game menu
//
//      Floating Pause Menu
//      1. Resume -> Closes menu + Unpaues Game
//      2. Settings -> Closes menu + Opens floating settings menu
//      3. Return to Main Menu -> Ends game and returns to main menu
//      4. Return to Desktop -> Ends game and closes app
//
//      Floating EndGame Menu
//      1. Outcome Text Field -> Diplays "You Win!" or "You Lose" based on score
//      2. Play Again -> Ends game and starts a new game
//      3. Return to Main Menu -> Ends game and returns to main menu
//      4. Return to Desktop -> Ends game and closes app
//
//  Game Asstes
//      Textures
//      1. Paddle
//      2. Ball
//      3. Game Background
//      4. Score Numbers Font
//      5. Dotted Line
//      6. Walls
//      7. Z-Pong Logo
//      8. UI -> IDK what I will need yet
//      9. UI Font
//      10. Main Menu Background
//
//      Audio
//      1. Menu Click (Sfx)
//      2. Ball Hit Paddle (Sfx)
//      3. Ball Hit Wall (Sfx)
//      4. Ball Score (Sfx)
//      5. Game Win (Sfx)
//      6. Game Lose (Sfx)
//      7. Menu Theme (Music, Looping)
//      8. Game Theme (Music, Looping)
//
//  UI/Menu
//      Widgets
//      1. Text
//      2. Buttons
//      3. Sliders
//      4. Checkbox
//      5. Box/Window
//      6. Binding Icon Display -> Displays Mouse/Keyboard/Controller symbols
//
//
//
