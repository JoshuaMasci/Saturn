const std = @import("std");

const Shader = @import("shader.zig");
pub const DirectoryMeta = Shader.DirectoryMeta;

const c = @cImport({
    @cInclude("glslang/Include/glslang_c_interface.h");
    @cInclude("glslang/Public/resource_limits_c.h");
});

var global_initialized: bool = false;
pub fn init() !void {
    std.debug.assert(!global_initialized);
    if (c.glslang_initialize_process() == 0) {
        return error.GlslangInitFailed;
    }
    global_initialized = true;
}

pub fn deinit() void {
    std.debug.assert(global_initialized);
    c.glslang_finalize_process();
    global_initialized = false;
}

pub const CompileGlslError = error{
    ShaderCreateFailed,
    PreprocessFailed,
    ParseFailed,
    ProgramCreateFailed,
    LinkFailed,
    OutOfMemory,
    IncludeNotFound,
};

const IncludeResult = struct {
    header_name: []const u8,
    header_data: []const u8,
    allocator: std.mem.Allocator,

    fn deinit(self: *IncludeResult) void {
        self.allocator.free(self.header_name);
        self.allocator.free(self.header_data);
    }
};

const IncludeContext = struct {
    allocator: std.mem.Allocator,
    shader_dir: std.fs.Dir,
    results: std.ArrayList(*IncludeResult),

    fn init(
        allocator: std.mem.Allocator,
        shader_dir: std.fs.Dir,
    ) IncludeContext {
        return .{
            .allocator = allocator,
            .shader_dir = shader_dir,
            .results = .empty,
        };
    }

    fn deinit(self: *IncludeContext) void {
        for (self.results.items) |result| {
            result.deinit();
            self.allocator.destroy(result);
        }
        self.results.deinit(self.allocator);
    }
};

fn includeLocalCallback(
    ctx: ?*anyopaque,
    header_name: [*c]const u8,
    includer_name: [*c]const u8,
    include_depth: usize,
) callconv(.c) [*c]c.glsl_include_result_t {
    _ = includer_name;
    _ = include_depth;

    const context: *IncludeContext = @ptrCast(@alignCast(ctx orelse return null));
    return loadIncludeFile(context, header_name) catch return null;
}

fn includeSystemCallback(
    ctx: ?*anyopaque,
    header_name: [*c]const u8,
    includer_name: [*c]const u8,
    include_depth: usize,
) callconv(.c) [*c]c.glsl_include_result_t {
    _ = includer_name;
    _ = include_depth;

    const context: *IncludeContext = @ptrCast(@alignCast(ctx orelse return null));
    return loadIncludeFile(context, header_name) catch return null;
}

fn loadIncludeFile(
    context: *IncludeContext,
    header_name: [*c]const u8,
) !*c.glsl_include_result_t {
    const header_name_slice = try context.allocator.dupe(u8, std.mem.span(header_name));
    errdefer context.allocator.free(header_name_slice);

    const file = try context.shader_dir.openFile(header_name_slice, .{});
    defer file.close();
    const content = try file.readToEndAlloc(context.allocator, 10 * 1024 * 1024);
    errdefer context.allocator.free(content);

    // Create result structure
    const result = try context.allocator.create(IncludeResult);
    errdefer context.allocator.destroy(result);

    result.* = .{
        .header_name = header_name_slice,
        .header_data = content,
        .allocator = context.allocator,
    };

    // Track for cleanup
    try context.results.append(context.allocator, result);

    // Create C result
    const c_result = try context.allocator.create(c.glsl_include_result_t);

    c_result.* = .{
        .header_name = result.header_name.ptr,
        .header_data = result.header_data.ptr,
        .header_length = result.header_data.len,
    };

    return c_result;
}

fn freeIncludeCallback(
    ctx: ?*anyopaque,
    result: [*c]c.glsl_include_result_t,
) callconv(.c) c_int {
    const context: *IncludeContext = @ptrCast(@alignCast(ctx orelse return 0));
    const result_ptr_opt: ?*c.glsl_include_result_t = @ptrCast(result);
    if (result_ptr_opt) |result_ptr| {
        context.allocator.destroy(result_ptr);
    }
    return 0;
}

pub fn compileGlslToSpirv(
    allocator: std.mem.Allocator,
    shader_dir: std.fs.Dir,
    shader_name: []const u8,
    shader_code: []const u8,
    shader_stage: Shader.Stage,
) CompileGlslError!Shader {
    const glsl_shader_stage: c_uint = switch (shader_stage) {
        .vertex => c.GLSLANG_STAGE_VERTEX,
        .fragment => c.GLSLANG_STAGE_FRAGMENT,
        .compute => c.GLSLANG_STAGE_COMPUTE,
        .task => c.GLSLANG_STAGE_TASK,
        .mesh => c.GLSLANG_STAGE_MESH,
    };

    var include_ctx = IncludeContext.init(allocator, shader_dir);
    defer include_ctx.deinit();

    const callbacks = c.glsl_include_callbacks_t{
        .include_system = includeSystemCallback,
        .include_local = includeLocalCallback,
        .free_include_result = freeIncludeCallback,
    };

    const glsl_input: c.glslang_input_t = .{
        .language = c.GLSLANG_SOURCE_GLSL,
        .stage = glsl_shader_stage,
        .client = c.GLSLANG_CLIENT_VULKAN,
        .client_version = c.GLSLANG_TARGET_VULKAN_1_2,
        .target_language = c.GLSLANG_TARGET_SPV,
        .target_language_version = c.GLSLANG_TARGET_SPV_1_5,
        .code = shader_code.ptr,
        .default_version = 100,
        .default_profile = c.GLSLANG_NO_PROFILE,
        .force_default_version_and_profile = c.false,
        .forward_compatible = c.false,
        .messages = c.GLSLANG_MSG_DEFAULT_BIT,
        .resource = c.glslang_default_resource(),
        .callbacks = callbacks,
        .callbacks_ctx = &include_ctx,
    };

    const shader = c.glslang_shader_create(&glsl_input);
    if (shader == null) {
        std.log.err("GLSL creation failed: {s}\n{s}\n{s}", .{
            shader_name,
            c.glslang_shader_get_info_log(shader),
            c.glslang_shader_get_info_debug_log(shader),
        });
        return error.ShaderCreateFailed;
    }
    defer c.glslang_shader_delete(shader);

    if (c.glslang_shader_preprocess(shader, &glsl_input) == c.false) {
        std.log.err("GLSL preprocessing failed: {s}\n{s}\n{s}", .{
            shader_name,
            c.glslang_shader_get_info_log(shader),
            c.glslang_shader_get_info_debug_log(shader),
        });
        return error.PreprocessFailed;
    }

    if (c.glslang_shader_parse(shader, &glsl_input) == c.false) {
        std.log.err("GLSL parsing failed: {s}\n{s}\n{s}\n{s}", .{
            shader_name,
            c.glslang_shader_get_info_log(shader),
            c.glslang_shader_get_info_debug_log(shader),
            c.glslang_shader_get_preprocessed_code(shader),
        });
        return error.ParseFailed;
    }

    const program = c.glslang_program_create();
    if (program == null)
        return error.ProgramCreateFailed;
    defer c.glslang_program_delete(program);
    c.glslang_program_add_shader(program, shader);

    if (c.glslang_program_link(program, c.GLSLANG_MSG_SPV_RULES_BIT | c.GLSLANG_MSG_VULKAN_RULES_BIT) == c.false) {
        std.log.err("GLSL linking failed: {s}\n{s}\n{s}", .{
            shader_name,
            c.glslang_shader_get_info_log(shader),
            c.glslang_shader_get_info_debug_log(shader),
        });
        return error.LinkFailed;
    }

    c.glslang_program_SPIRV_generate(program, glsl_shader_stage);

    const spirv_code_count = c.glslang_program_SPIRV_get_size(program);
    const spirv_code = try allocator.alloc(u32, spirv_code_count);
    errdefer allocator.free(spirv_code);

    c.glslang_program_SPIRV_get(program, spirv_code.ptr);

    return .{
        .name = try allocator.dupe(u8, shader_name),
        .target = .vulkan,
        .stage = shader_stage,
        .bindings = .{},
        .spirv_code = spirv_code,
    };
}
