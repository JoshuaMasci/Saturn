const std = @import("std");
const dxc = @import("dxc");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const vertex_shader_source =
        \\struct VSInput {
        \\    float3 position : POSITION;
        \\    float2 texcoord : TEXCOORD0;
        \\};
        \\
        \\struct VSOutput {
        \\    float4 position : SV_POSITION;
        \\    float2 texcoord : TEXCOORD0;
        \\};
        \\
        \\VSOutput main(VSInput input) {
        \\    VSOutput output;
        \\    output.position = float4(input.position, 1.0);
        \\    output.texcoord = input.texcoord;
        \\    return output;
        \\}
    ;

    const pixel_shader_source =
        \\struct PSInput {
        \\    float4 position : SV_POSITION;
        \\    float2 texcoord : TEXCOORD0;
        \\};
        \\
        \\float4 main(PSInput input) : SV_TARGET {
        \\    return float4(input.texcoord, 0.0, 1.0);
        \\}
    ;

    const compute_shader_source =
        \\RWTexture2D<float4> OutputTexture : register(u0);
        \\
        \\[numthreads(8, 8, 1)]
        \\void main(uint3 id : SV_DispatchThreadID) {
        \\    float2 uv = float2(id.xy) / float2(512.0, 512.0);
        \\    OutputTexture[id.xy] = float4(uv, 0.0, 1.0);
        \\}
    ;

    std.log.info("Compiling shaders with DXC...", .{});

    std.log.info("Compiling vertex shader...", .{});
    const vs_result = dxc.compileVertexShader(
        allocator,
        vertex_shader_source,
        "main",
    ) catch |err| {
        std.log.err("Failed to compile vertex shader: {}", .{err});
        return;
    };
    defer vs_result.deinit();
    std.log.info("✓ Vertex shader compiled successfully ({} bytes of SPIR-V)", .{vs_result.spirv_data.len});

    std.log.info("Compiling pixel shader...", .{});
    const ps_result = dxc.compilePixelShader(
        allocator,
        pixel_shader_source,
        "main",
    ) catch |err| {
        std.log.err("Failed to compile pixel shader: {}", .{err});
        return;
    };
    defer ps_result.deinit();
    std.log.info("✓ Pixel shader compiled successfully ({} bytes of SPIR-V)", .{ps_result.spirv_data.len});

    std.log.info("Compiling compute shader...", .{});
    const cs_result = dxc.compileComputeShader(
        allocator,
        compute_shader_source,
        "main",
    ) catch |err| {
        std.log.err("Failed to compile compute shader: {}", .{err});
        return;
    };
    defer cs_result.deinit();
    std.log.info("✓ Compute shader compiled successfully ({} bytes of SPIR-V)", .{cs_result.spirv_data.len});

    try std.fs.cwd().writeFile(.{ .sub_path = "vertex_shader.spv", .data = vs_result.spirv_data });
    try std.fs.cwd().writeFile(.{ .sub_path = "pixel_shader.spv", .data = ps_result.spirv_data });
    try std.fs.cwd().writeFile(.{ .sub_path = "compute_shader.spv", .data = cs_result.spirv_data });

    std.log.info("✓ All shaders compiled and saved successfully!", .{});
    std.log.info("Generated files:", .{});
    std.log.info("  - vertex_shader.spv ({} bytes)", .{vs_result.spirv_data.len});
    std.log.info("  - pixel_shader.spv ({} bytes)", .{ps_result.spirv_data.len});
    std.log.info("  - compute_shader.spv ({} bytes)", .{cs_result.spirv_data.len});

    std.log.info("\nUsing lower-level API...", .{});
    const compiler = try dxc.Compiler.init();
    defer compiler.deinit();

    const custom_result = try compiler.compileHlslToSpirv(
        allocator,
        "float4 main() : SV_TARGET { return float4(1.0, 1.0, 0.0, 1.0); }",
        "main",
        "ps_6_0",
    );
    defer custom_result.deinit();
    std.log.info("✓ Custom compilation successful ({} bytes)", .{custom_result.spirv_data.len});
}
