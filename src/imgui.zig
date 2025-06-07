const std = @import("std");
const zimgui = @import("zimgui");

pub const gui = zimgui;

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !Self {
    zimgui.init(allocator);

    //TODO: support viewports
    zimgui.io.setConfigFlags(.{ .dock_enable = true, .viewport_enable = false });

    return .{};
}

pub fn deinit(self: Self) void {
    _ = self; // autofix
    zimgui.deinit();
}

pub fn updateInput(self: Self, input: *@import("platform/sdl3.zig").Input) void {
    _ = self; // autofix

    if (input.isMouseCaptured()) {
        const neg_inf: f32 = -std.math.inf(f32);
        zimgui.io.addMouseButtonEvent(.left, false);
        zimgui.io.addMouseButtonEvent(.middle, false);
        zimgui.io.addMouseButtonEvent(.right, false);
        zimgui.io.addMousePositionEvent(neg_inf, neg_inf);
    } else {
        zimgui.io.addMouseButtonEvent(.left, input.isMouseDown(.left));
        zimgui.io.addMouseButtonEvent(.middle, input.isMouseDown(.middle));
        zimgui.io.addMouseButtonEvent(.right, input.isMouseDown(.right));

        const pos = input.getMousePosition().?;
        zimgui.io.addMousePositionEvent(pos[0], pos[1]);

        //TODO: this
        //zimgui.io.addInputCharactersUTF8(null);
    }
}

pub fn startFrame(self: Self, window_size: [2]u32, delta_time: f32) void {
    _ = self; // autofix
    zimgui.io.setDisplaySize(@floatFromInt(window_size[0]), @floatFromInt(window_size[1]));
    zimgui.io.setDeltaTime(delta_time);
    zimgui.newFrame();
}

pub fn createFullscreenDockspace(self: Self, dockspace_name: [:0]const u8) zimgui.Ident {
    _ = self; // autofix
    const viewport = zimgui.getMainViewport();
    const pos = viewport.getPos();
    const size = viewport.getSize();

    zimgui.setNextWindowPos(.{ .x = pos[0], .y = pos[1] });
    zimgui.setNextWindowSize(.{ .w = size[0], .h = size[1] });
    zimgui.setNextWindowViewport(viewport.getId());
    zimgui.pushStyleVar1f(.{ .idx = zimgui.StyleVar.window_rounding, .v = 0.0 });
    zimgui.pushStyleVar1f(.{ .idx = zimgui.StyleVar.window_border_size, .v = 0.0 });
    zimgui.pushStyleVar2f(.{ .idx = zimgui.StyleVar.window_padding, .v = .{ 0.0, 0.0 } });
    defer zimgui.popStyleVar(.{ .count = 3 });
    zimgui.pushStyleColor4f(.{ .idx = zimgui.StyleCol.window_bg, .c = .{ 0.0, 0.0, 0.0, 0.0 } });
    defer zimgui.popStyleColor(.{ .count = 1 });

    const window_flags = zimgui.WindowFlags{
        .no_scrollbar = true,
        .no_docking = true,
        .no_title_bar = true,
        .no_collapse = true,
        .no_resize = true,
        .no_move = true,
        .no_bring_to_front_on_focus = true,
        .no_nav_focus = true,
        .no_nav_inputs = true,
        .always_auto_resize = true,
        .no_background = true,
    };

    // Important: note that we proceed even if Begin() returns false (aka window is collapsed).
    // This is because we want to keep our DockSpace() active. If a DockSpace() is inactive,
    // all active windows docked into it will lose their parent and become undocked.
    // We cannot preserve the docking relationship between an active window and an inactive docking, otherwise
    // any change of dockspace/settings would lead to windows being stuck in limbo and never being visible.
    var open = true;
    _ = zimgui.begin(dockspace_name, .{
        .popen = &open,
        .flags = window_flags,
    });

    return zimgui.DockSpace(
        dockspace_name,
        size,
        .{ .passthru_central_node = true },
    );
}

//TODO: render using backend
pub fn render(self: Self) void {
    zimgui.endFrame();

    _ = self; // autofix
    zimgui.render();
    const draw_data = zimgui.getDrawData();
    _ = draw_data; // autofix
}
