# Saturn Game Framework

## RoadMap (Subject to change)

### V0.1 (Done)
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
- Rewrite physics allocator functions to get rid of hashmap

### V0.2
- Job System for game/physics
- Add meshoptimizer to asset processing
- Custom Vulkan renderer
	- Add debug labels
	- Sync2
	- host_image_copy
	- Imgui
- Switch libraries (SDL, Vulkan, and zdxc) to use zig allocator in place of libc malloc/free
- Input binding config files

### V0.3
- Switch subsystems to zig modules
- Audio (Either from Sdl3 or SteamAudio)
- First pass on lighting/shading
- Investigate the Slang shading language
- Networking (Either from Sdl3 or SteamNetworking)
- Save/Load system
- Example projects
- Imgui viewport support
- Tracy integration

### Someday Maybe
- Android build target
- Metal Rendering, IOS build target (If I buy a Mac)
- meshshading, rtx, workgraphs
