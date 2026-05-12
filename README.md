# Saturn Game Framework

A game framework written in Zig with focus on performance and simplicity.

## Features

- SDL3 integration for windowing, input, and rendering
- Vulkan renderer support
- Jolt Physics integration
- Dear ImGui for debug interfaces
- Asset processing pipeline

## Requirements

- Zig 0.15.1
- Vulkan SDK (for graphics)
- System dependencies:
  - Linux: meshoptimizer, glslang
  - Windows: Not Supported Yet
  - macOS: Not Supported Yet

## Building

Clone the repository with submodules:
```bash
git clone --recursive https://github.com/your-repo/Saturn.git
cd Saturn
```

Build the project:
```bash

# Build and runs the assets pipeline
zig build assets

# Build and runs the assets pipeline only on engine assets
zig build engine-assets

# Build and runs the assets pipeline only on untracked game assets
zig build game-assets

# Builds and runs the game test project
zig build run

```

## License

See LICENSE.md for details.
