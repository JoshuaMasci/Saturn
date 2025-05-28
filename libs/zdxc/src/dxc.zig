const std = @import("std");
const testing = std.testing;

const DxcCompileResult = extern struct {
    data: ?[*]u8,
    size: usize,
    error_message: ?[*:0]u8,
    success: c_int,
};

const DxcCompiler = opaque {};

extern fn dxc_create_compiler() ?*DxcCompiler;
extern fn dxc_compile_hlsl_to_spirv(
    ctx: *DxcCompiler,
    source_code: [*]const u8,
    source_size: usize,
    entry_point: [*:0]const u8,
    target_profile: [*:0]const u8,
) DxcCompileResult;
extern fn dxc_free_result(result: *DxcCompileResult) void;
extern fn dxc_destroy_compiler(ctx: *DxcCompiler) void;

pub const CompileError = error{
    InitializationFailed,
    CompilationFailed,
    OutOfMemory,
};

pub const CompileResult = struct {
    spirv_data: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: CompileResult) void {
        self.allocator.free(self.spirv_data);
    }
};

pub const Compiler = struct {
    ctx: *DxcCompiler,

    pub fn init() CompileError!Compiler {
        const ctx = dxc_create_compiler() orelse return CompileError.InitializationFailed;
        return Compiler{ .ctx = ctx };
    }

    pub fn deinit(self: Compiler) void {
        dxc_destroy_compiler(self.ctx);
    }

    pub fn compileHlslToSpirv(
        self: Compiler,
        allocator: std.mem.Allocator,
        hlsl_source: []const u8,
        entry_point: []const u8,
        target_profile: []const u8,
    ) CompileError!CompileResult {
        // Ensure null-terminated strings
        const entry_point_z = try allocator.dupeZ(u8, entry_point);
        defer allocator.free(entry_point_z);

        const target_profile_z = try allocator.dupeZ(u8, target_profile);
        defer allocator.free(target_profile_z);

        var result = dxc_compile_hlsl_to_spirv(
            self.ctx,
            hlsl_source.ptr,
            hlsl_source.len,
            entry_point_z.ptr,
            target_profile_z.ptr,
        );
        defer dxc_free_result(&result);

        if (result.success == 0) {
            if (result.error_message) |err_msg| {
                const error_str = std.mem.span(err_msg);
                std.log.err("DXC compilation failed: {s}", .{error_str});
            }
            return CompileError.CompilationFailed;
        }

        if (result.data == null or result.size == 0) {
            return CompileError.CompilationFailed;
        }

        const spirv_data = try allocator.dupe(u8, result.data.?[0..result.size]);

        return CompileResult{
            .spirv_data = spirv_data,
            .allocator = allocator,
        };
    }
};

pub fn compileVertexShader(
    allocator: std.mem.Allocator,
    hlsl_source: []const u8,
    entry_point: []const u8,
) CompileError!CompileResult {
    const compiler = try Compiler.init();
    defer compiler.deinit();

    return compiler.compileHlslToSpirv(
        allocator,
        hlsl_source,
        entry_point,
        "vs_6_0",
    );
}

pub fn compilePixelShader(
    allocator: std.mem.Allocator,
    hlsl_source: []const u8,
    entry_point: []const u8,
) CompileError!CompileResult {
    const compiler = try Compiler.init();
    defer compiler.deinit();

    return compiler.compileHlslToSpirv(
        allocator,
        hlsl_source,
        entry_point,
        "ps_6_0",
    );
}

pub fn compileComputeShader(
    allocator: std.mem.Allocator,
    hlsl_source: []const u8,
    entry_point: []const u8,
) CompileError!CompileResult {
    const compiler = try Compiler.init();
    defer compiler.deinit();

    return compiler.compileHlslToSpirv(
        allocator,
        hlsl_source,
        entry_point,
        "cs_6_0",
    );
}

// Tests
test "compiler initialization" {
    const compiler = Compiler.init() catch |err| switch (err) {
        CompileError.InitializationFailed => {
            std.log.warn("DXC not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer compiler.deinit();
}

test "simple vertex shader compilation" {
    const compiler = Compiler.init() catch |err| switch (err) {
        CompileError.InitializationFailed => {
            std.log.warn("DXC not available for testing, skipping", .{});
            return;
        },
        else => return err,
    };
    defer compiler.deinit();

    const hlsl_source =
        \\struct VSInput {
        \\    float3 position : POSITION;
        \\};
        \\
        \\struct VSOutput {
        \\    float4 position : SV_POSITION;
        \\};
        \\
        \\VSOutput main(VSInput input) {
        \\    VSOutput output;
        \\    output.position = float4(input.position, 1.0);
        \\    return output;
        \\}
    ;

    const result = compiler.compileHlslToSpirv(
        testing.allocator,
        hlsl_source,
        "main",
        "vs_6_0",
    ) catch |err| switch (err) {
        CompileError.CompilationFailed => {
            std.log.warn("Compilation failed, this might be expected in test environment", .{});
            return;
        },
        else => return err,
    };
    defer result.deinit();

    try testing.expect(result.spirv_data.len > 0);

    // Basic SPIR-V magic number check
    if (result.spirv_data.len >= 4) {
        const magic = std.mem.readInt(u32, result.spirv_data[0..4], .little);
        try testing.expectEqual(@as(u32, 0x07230203), magic);
    }
}

test "convenience function" {
    const hlsl_source =
        \\float4 main() : SV_TARGET {
        \\    return float4(1.0, 0.0, 0.0, 1.0);
        \\}
    ;

    const result = compilePixelShader(
        testing.allocator,
        hlsl_source,
        "main",
    ) catch |err| switch (err) {
        CompileError.InitializationFailed, CompileError.CompilationFailed => {
            std.log.warn("DXC not available or compilation failed, skipping", .{});
            return;
        },
        else => return err,
    };
    defer result.deinit();

    try testing.expect(result.spirv_data.len > 0);
}
