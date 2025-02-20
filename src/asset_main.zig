const std = @import("std");

var input_dir: std.fs.Dir = undefined;
var output_dir: std.fs.Dir = undefined;

pub const ProcessFn = *const fn (allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8;

//Asset Types
const hlsl = @import("asset/hlsl.zig");

pub fn main() !void {
    if (hlsl.init()) {
        return error.shaderCompilerInitFailed;
    }
    defer hlsl.deinit();

    const base_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    const arena_allocator = arena.allocator();

    var args = std.process.args();
    _ = args.next() orelse std.debug.panic("Failed to read process name, honestly IDK how this happens", .{});
    const input_path = args.next() orelse std.debug.panic("Failed to read input path", .{});
    const output_path = args.next() orelse std.debug.panic("Failed to read output path", .{});

    std.log.info("Input Dir: {s}", .{input_path});
    std.log.info("Output Dir: {s}", .{output_path});

    try std.fs.cwd().makePath(output_path);

    input_dir = try std.fs.cwd().openDir(input_path, .{ .iterate = true });
    defer input_dir.close();

    output_dir = try std.fs.cwd().openDir(output_path, .{});
    defer output_dir.close();

    var walker = try input_dir.walk(base_allocator);
    defer walker.deinit();

    var process_fns = std.StringHashMap(ProcessFn).init(base_allocator);
    defer process_fns.deinit();

    try process_fns.put(".obj", processObj);
    try process_fns.put(".png", processStb);
    try process_fns.put(".json_mat", processMaterial);
    try process_fns.put(".hlsl", processShader);

    while (try walker.next()) |entry| {
        _ = arena.reset(.retain_capacity); // I don't care if it failes for some reason, we'll just waste some memory as a treat
        if (entry.kind == .file) {
            const meta_file_ext = std.fs.path.extension(entry.basename);
            if (std.mem.eql(u8, meta_file_ext, ".meta")) {

                // Get the file ext of real file
                const file_ext = std.fs.path.extension(std.fs.path.stem(entry.basename));

                if (process_fns.get(file_ext)) |process_fn| {
                    if (process_fn(arena_allocator, entry.path)) |err| {
                        std.log.err("Failed to process file {s} -> {s}", .{ entry.path, err });
                    } else {
                        std.log.info("Succesfully processed file {s}", .{entry.path});
                    }
                } else {
                    std.log.warn("Unknown meta file type: {s}", .{file_ext});
                }
            }
        }
    }
}

fn removeExt(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    return path[0..(path.len - ext.len)];
}

fn replaceExt(allocator: std.mem.Allocator, path: []const u8, new_ext: []const u8) ![]const u8 {
    const current_ext = std.fs.path.extension(path);
    if (current_ext.len == 0) {
        unreachable;
    } else {
        const base_path_len = path.len - current_ext.len;
        const new_len = base_path_len + new_ext.len;
        var new_path = try allocator.alloc(u8, new_len);
        std.mem.copyForwards(u8, new_path, path[0..base_path_len]);
        std.mem.copyForwards(u8, new_path[base_path_len..], new_ext);
        return new_path;
    }
}

fn makePath(dir: std.fs.Dir, file_path: []const u8) void {
    if (std.fs.path.dirname(file_path)) |dir_path| {
        dir.makePath(dir_path) catch return;
    }
}

fn errorString(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, fmt, args) catch "Failed to alloc string";
}

fn processObj(allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8 {
    const file_path = removeExt(meta_file_path);

    const obj = @import("asset/obj.zig");
    const processed_mesh = obj.loadObjMesh(allocator, input_dir, file_path) catch |err|
        return errorString(allocator, "Failed to open obj({s}): {}", .{ file_path, err });

    const new_path = replaceExt(allocator, file_path, ".mesh") catch |err|
        return errorString(allocator, "Failed to allocate string: {}", .{err});

    defer allocator.free(new_path);

    makePath(output_dir, new_path);
    const output_file = output_dir.createFile(new_path, .{}) catch |err|
        return errorString(allocator, "Failed to create file: {}", .{err});
    defer output_file.close();

    processed_mesh.serialize(output_file.writer()) catch |err|
        return errorString(allocator, "Failed to serialize file: {}", .{err});

    return null;
}

fn processStb(allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8 {
    const file_path = removeExt(meta_file_path);

    const stbi = @import("asset/stbi.zig");
    const texture = stbi.loadTexture2d(allocator, input_dir, file_path) catch |err|
        return errorString(allocator, "Failed to open file({s}): {}", .{ file_path, err });

    const new_path = replaceExt(allocator, file_path, ".tex2d") catch |err|
        return errorString(allocator, "Failed to allocate string: {}", .{err});
    defer allocator.free(new_path);

    makePath(output_dir, new_path);
    const output_file = output_dir.createFile(new_path, .{}) catch |err|
        return errorString(allocator, "Failed to create file: {}", .{err});
    defer output_file.close();

    texture.serialize(output_file.writer()) catch |err|
        return errorString(allocator, "Failed to serialize file: {}", .{err});

    return null;
}

fn processMaterial(allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8 {
    const file_path = removeExt(meta_file_path);

    const file_buffer = input_dir.readFileAllocOptions(allocator, file_path, std.math.maxInt(usize), null, 4, null) catch |err|
        return errorString(allocator, "Failed to read file({s}): {}", .{ file_path, err });

    defer allocator.free(file_buffer);

    const new_path = replaceExt(allocator, file_path, ".json_mat") catch |err|
        return errorString(allocator, "Failed to allocate string: {}", .{err});
    defer allocator.free(new_path);

    makePath(output_dir, new_path);
    const output_file = output_dir.createFile(new_path, .{}) catch |err|
        return errorString(allocator, "Failed to create file: {}", .{err});
    defer output_file.close();

    // Just write the pure json file for now
    // TODO: at least convert from source asset path to AssetRegistry strings?
    output_file.writeAll(file_buffer) catch |err|
        return errorString(allocator, "Failed to write file: {}", .{err});

    return null;
}

fn processShader(allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8 {
    const file_path = removeExt(meta_file_path);

    const shader = hlsl.compileShader(allocator, input_dir, file_path) catch |err|
        return errorString(allocator, "Failed to compile shader: {}", .{err});

    const new_path = replaceExt(allocator, file_path, ".shader") catch |err|
        return errorString(allocator, "Failed to allocate string: {}", .{err});
    defer allocator.free(new_path);

    makePath(output_dir, new_path);
    const output_file = output_dir.createFile(new_path, .{}) catch |err|
        return errorString(allocator, "Failed to create file: {}", .{err});
    defer output_file.close();

    shader.serialize(output_file.writer()) catch |err|
        return errorString(allocator, "Failed to serialize file: {}", .{err});

    return null;
}
