const saturn_options = @import("saturn_options");

const sdl2 = @import("platform/sdl2.zig");
pub fn getPlatform() type {
	return sdl2.Platform;
}

const OpenglContext = @import("rendering/opengl/context.zig").Sdl2Context;
pub fn getWindow() type {
	return OpenglContext;
}

const Renderer = @import("rendering/renderer.zig").Renderer;
pub fn getRenderer() type {
	return Renderer;
}
