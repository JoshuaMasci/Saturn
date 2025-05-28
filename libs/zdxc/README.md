# DXC Zig Wrapper

A Zig 0.14.0 library that wraps the DirectXShaderCompiler (DXC) to compile HLSL shaders to SPIR-V.

## Prerequisites

You need to have DXC installed on your system. The library and headers should be available in your system paths.

### Ubuntu/Debian
```bash
sudo apt install spirv-tools libdxcompiler-dev
```

### Arch Linux
```bash
sudo pacman -S directx-shader-compiler spirv-tools
```

### macOS (via Homebrew)
```bash
brew install directx-shader-compiler
```

### Windows
Download and install the DirectX Shader Compiler from the Microsoft GitHub releases.

## Usage

### Basic Example

```zig
const std = @import("std");
const dxc = @import("dxc");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const hlsl_source =
        \\float4 main() : SV_TARGET {
        \\    return float4(1.0, 0.0, 0.0, 1.0);
        \\}
    ;

    // Compile pixel shader using convenience function
    const result = try dxc.compilePixelShader(
        allocator,
        hlsl_source,
        "main",
    );
    defer result.deinit();

    // The result.spirv_data contains the compiled SPIR-V bytecode
    std.log.info("Compiled shader: {} bytes of SPIR-V", .{result.spirv_data.len});

    // Save to file
    try std.fs.cwd().writeFile("shader.spv", result.spirv_data);
}
```

### Using the Lower-Level API

```zig
const compiler = try dxc.Compiler.init();
defer compiler.deinit();

const result = try compiler.compileHlslToSpirv(
    allocator,
    hlsl_source,
    "main",           // entry point
    "vs_6_0",        // target profile
);
defer result.deinit();
```

### Convenience Functions

The library provides convenience functions for common shader types:

```zig
// Vertex shader (target: vs_6_0)
const vs_result = try dxc.compileVertexShader(allocator, hlsl_source, "main");

// Pixel shader (target: ps_6_0)
const ps_result = try dxc.compilePixelShader(allocator, hlsl_source, "main");

// Compute shader (target: cs_6_0)
const cs_result = try dxc.compileComputeShader(allocator, hlsl_source, "main");
```

## Building

```bash
# Build the library
zig build

# Run tests
zig build test

# Run the example
zig build run

# Install (copies artifacts to zig-out/)
zig build install
```

## Integration

To use this library in your project, add it as a dependency in your `build.zig.zon`:

```zig
const zdxc = b.dependency("zdxc", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("dxc", zdxc.module("dxc"));
```
