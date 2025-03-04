const saturn_options = @import("saturn_options");

pub fn getPlatform() type {
    if (saturn_options.sdl3) {
        return @import("platform/sdl3.zig").Platform;
    } else {
        return @import("platform/sdl2.zig").Platform;
    }
}

pub fn getWindow() type {
    if (saturn_options.sdl3) {
        return @import("platform/sdl3.zig").Window;
    } else {
        @compileError("Unimpliemnted for sdl2");
    }
}

pub fn getRenderer() type {
    if (saturn_options.sdl3) {
        return @import("rendering/sdl_gpu/renderer.zig").Renderer;
    } else {
        return @import("rendering/opengl/renderer.zig").Renderer;
    }
}
