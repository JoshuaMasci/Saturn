const saturn_options = @import("saturn_options");

pub fn getPlatform() type {
    return @import("platform/sdl3.zig").Platform;
}

pub fn getWindow() type {
    return @import("platform/sdl3.zig").Window;
}

pub fn getRenderer() type {
    return @import("rendering/sdl_gpu/renderer.zig").Renderer;
}
