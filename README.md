# Saturn Game Framework

## RoadMap (Subject to change)

### V0.1
- Move entities between worlds
- Global entity list + entity create/delete in systems
- Comptime hash based entity components/systems
- Sdl3
	- Windowing
	- Input
		- Keyboard/Mouse
		- Gamepad
		- Joystick
	- SDL_GPU rendering
	- Dear imgui (using sdl3 backend)
- Physics Debug Renderer

### V0.2
- Audio (Either from Sdl3 or SteamAudio)
- First pass on lighting/shading
- Job System for game/physics
- Add meshoptimizer to asset processing 
- Rewrite physics allocator functions to get rid of hashmap

### V0.3
- Switch subsystems to zig modules
- Networking (Either from Sdl3 or SteamNetworking)
- Save/Load system
- Example projects

### Someday Maybe
- Custom Vulkan renderer
	- using meshshading, rtx, workgraphs
- Android build target
