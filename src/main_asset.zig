// Main File for Asset Pipeline

const std = @import("std");

const Gltf = @import("asset/gltf.zig");
const AssetType = @import("asset/header.zig").AssetType;
const hlsl = @import("asset/hlsl.zig");
const io = @import("asset/io.zig");
const Material = @import("asset/material.zig");
const obj = @import("asset/obj.zig");
const stbi = @import("asset/stbi.zig");

pub const ProcessFn = *const fn (allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8;

pub const MetaFileBase = struct {
    type: []const u8,
};

fn HandleError(func: anytype) type {
    return struct {
        fn process(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
            func(allocator, path) catch |err| {
                return errorString(allocator, "{}", .{err});
                //std.log.err("Failed to process file {s} -> {s}", .{ path, err });
                // _ = error_count.fetchAnd(1, .monotonic);
            };
            //std.log.info("Succesfully processed file {s}", .{path});
            return null;
        }
    };
}

pub fn thread_worker(process_fn: ProcessFn, path: []const u8) void {
    defer global_allocator.free(path);

    if (process_fn(global_allocator, path)) |err| {
        std.log.err("Failed to process file {s} -> {s}", .{ path, err });
        _ = error_count.fetchAnd(1, .monotonic);
        global_allocator.free(err);
    } else {
        std.log.info("Succesfully processed file {s}", .{path});
    }
}

pub fn readMetaType(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) ?[]const u8 {
    const meta_base = loadZonFile(MetaFileBase, allocator, dir, file_path, .{ .ignore_unknown_fields = true }) catch return null;
    defer std.zon.parse.free(allocator, meta_base);

    return allocator.dupe(u8, meta_base.type) catch null;
}

var repo_name: []const u8 = &.{};
var input_dir: std.fs.Dir = undefined;
var output_dir: std.fs.Dir = undefined;

var error_count = std.atomic.Value(usize).init(0);

var global_allocator: std.mem.Allocator = undefined;
var thread_pool: std.Thread.Pool = undefined;

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer if (debug_allocator.deinit() == .leak) {
        std.log.err("GeneralPurposeAllocator has a memory leak!", .{});
    };
    global_allocator = debug_allocator.allocator();

    try thread_pool.init(.{ .allocator = global_allocator });
    defer thread_pool.deinit();

    //Asset Init
    stbi.init(global_allocator);
    defer stbi.deinit();

    var args = std.process.args();
    _ = args.next() orelse std.debug.panic("Failed to read process name, honestly IDK how this happens", .{});
    repo_name = args.next() orelse std.debug.panic("Failed to read asset repo name", .{});
    const input_path = args.next() orelse std.debug.panic("Failed to read input path", .{});
    const output_path = args.next() orelse std.debug.panic("Failed to read output path", .{});

    std.log.info("Input Dir: {s}", .{input_path});
    std.log.info("Output Dir: {s}", .{output_path});

    try std.fs.cwd().makePath(output_path);

    input_dir = try std.fs.cwd().openDir(input_path, .{ .iterate = true });
    defer input_dir.close();

    output_dir = try std.fs.cwd().openDir(output_path, .{});
    defer output_dir.close();

    var process_fns = std.StringHashMap(ProcessFn).init(global_allocator);
    defer process_fns.deinit();

    //Textures
    try process_fns.put(".png", processStb);

    //Materials
    try process_fns.put(".json_mat", processMaterial);

    //Meshes
    {
        try process_fns.put(".obj", HandleError(processObj).process);
        try process_fns.put(".glb", processGltf);
        try process_fns.put(".gltf", processGltf);
    }

    //New approch that reads the "type" field of the metadata file do select callback
    var meta_type_process_fns = std.StringHashMap(ProcessFn).init(global_allocator);
    defer meta_type_process_fns.deinit();

    //Shaders
    {
        try meta_type_process_fns.put("shader-dir", HandleError(processShaderDir).process);
    }

    var wait_group = std.Thread.WaitGroup{};

    var walker = try input_dir.walk(global_allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const meta_file_ext = std.fs.path.extension(entry.basename);
            if (std.mem.eql(u8, meta_file_ext, ".meta")) {

                //New way of reading meta files
                if (readMetaType(global_allocator, input_dir, entry.path)) |meta_type| {
                    defer global_allocator.free(meta_type);
                    if (meta_type_process_fns.get(meta_type)) |process_fn| {
                        thread_pool.spawnWg(&wait_group, thread_worker, .{ process_fn, try global_allocator.dupe(u8, entry.path) });
                        continue;
                    }
                }

                // Get the file ext of real file
                const file_ext = std.fs.path.extension(std.fs.path.stem(entry.basename));

                if (process_fns.get(file_ext)) |process_fn| {
                    thread_pool.spawnWg(&wait_group, thread_worker, .{ process_fn, try global_allocator.dupe(u8, entry.path) });
                } else {
                    std.log.warn("Unknown meta file type: {s}", .{file_ext});
                }
            }
        }
    }

    thread_pool.waitAndWork(&wait_group);

    const failed = error_count.load(.monotonic);
    if (failed > 0) {
        std.log.err("Failed to proccess {} assets", .{failed});
        return error.failedToProccessAssets;
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

fn processObj(allocator: std.mem.Allocator, meta_file_path: []const u8) !void {
    const file_path = removeExt(meta_file_path);

    const processed_mesh = try obj.loadObjMesh(allocator, input_dir, file_path);
    defer processed_mesh.deinit(allocator);

    const new_path = try replaceExt(allocator, file_path, ".asset");
    defer allocator.free(new_path);

    try io.writeFile(output_dir, .mesh, new_path, processed_mesh);
}

fn processStb(allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8 {
    const file_path = removeExt(meta_file_path);

    const texture = stbi.loadFromFile(allocator, input_dir, std.fs.path.stem(file_path), file_path) catch |err|
        return errorString(allocator, "Failed to open file({s}): {}", .{ file_path, err });
    defer texture.deinit(allocator);

    const new_path = replaceExt(allocator, file_path, ".asset") catch |err|
        return errorString(allocator, "Failed to allocate string: {}", .{err});
    defer allocator.free(new_path);

    io.writeFile(output_dir, .texture, new_path, texture) catch |err|
        return errorString(allocator, "Failed to write asset file: {}", .{err});

    return null;
}

fn processMaterial(allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8 {
    const file_path = removeExt(meta_file_path);

    const json_material = Material.Json.read(allocator, input_dir, file_path) catch |err|
        return errorString(allocator, "Failed to parse json material({s}): {}", .{ file_path, err });
    defer json_material.deinit();

    const material = Material.initFromJson(allocator, &json_material.value) catch |err|
        return errorString(allocator, "Failed to parse create material({s}): {}", .{ file_path, err });
    defer material.deinit(allocator);

    const new_path = replaceExt(allocator, file_path, ".asset") catch |err|
        return errorString(allocator, "Failed to allocate string: {}", .{err});
    defer allocator.free(new_path);

    io.writeFile(output_dir, .material, new_path, material) catch |err|
        return errorString(allocator, "Failed to write asset file: {}", .{err});

    return null;
}

fn processShaderDir(allocator: std.mem.Allocator, meta_file_path: []const u8) !void {
    const meta_data = try loadZonFile(hlsl.DirectoryMeta, allocator, input_dir, meta_file_path, .{ .ignore_unknown_fields = true });
    defer std.zon.parse.free(allocator, meta_data);

    const shader_dir_path = std.fs.path.dirname(meta_file_path) orelse return error.failedToGetDirName;

    var shader_dir = try input_dir.openDir(shader_dir_path, .{ .iterate = true, .access_sub_paths = false });
    defer shader_dir.close();

    var shader_out_dir = try output_dir.makeOpenPath(shader_dir_path, .{});
    defer shader_out_dir.close();

    const compiler = try hlsl.Compiler.init(allocator, shader_dir, meta_data);
    defer compiler.deinit();

    var local_error_count: usize = 0;

    var walker = try shader_dir.walk(global_allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const shader_ext = std.fs.path.extension(entry.path);
            if (hlsl.getShaderStage(shader_ext)) |stage| {
                const shader_code = shader_dir.readFileAllocOptions(allocator, entry.path, std.math.maxInt(usize), null, .@"4", 0) catch |err| {
                    std.log.err("Failed to read shader {s}: {}", .{ entry.path, err });
                    local_error_count += 1;
                    continue;
                };
                defer allocator.free(shader_code);

                const shader = compiler.compile(allocator, entry.basename, shader_code, stage) catch |err| {
                    std.log.err("Failed to compile shader {s}: {}", .{ entry.path, err });
                    local_error_count += 1;
                    continue;
                };
                defer shader.deinit(allocator);

                const new_path = std.fmt.allocPrint(allocator, "{s}.asset", .{entry.path}) catch |err| {
                    std.log.err("Failed to allocate string: {}", .{err});
                    local_error_count += 1;
                    continue;
                };
                defer allocator.free(new_path);

                io.writeFile(shader_out_dir, .shader, new_path, shader) catch |err| {
                    std.log.err("Failed to write asset file: {}", .{err});
                    local_error_count += 1;
                    continue;
                };
            }
        }
    }

    if (local_error_count != 0) {
        return error.FailedToCompileShader;
    }
}

fn GltfResourceWorker(comptime load_fn: anytype, comptime asset_name: []const u8, comptime atype: AssetType) type {
    return struct {
        fn run(gltf_file: *Gltf, allocator: std.mem.Allocator, index: usize) void {
            if (load_fn(gltf_file.*, allocator, index)) |result| {
                defer result.value.deinit(allocator);

                const output_file_path = result.output_path;

                io.writeFile(output_dir, atype, output_file_path, result.value) catch |err| {
                    std.log.err("Failed to write asset file: {}", .{err});
                    return;
                };
            } else |err| {
                std.log.err("Failed to load " ++ asset_name ++ " {}: {}", .{ index, err });
            }
        }
    };
}
const mesh_thread_worker = GltfResourceWorker(Gltf.loadMesh, "mesh", .mesh).run;
const texture_thread_worker = GltfResourceWorker(Gltf.loadTexture, "texture", .texture).run;
const material_thread_worker = GltfResourceWorker(Gltf.loadMaterial, "material", .material).run;

fn processGltf(allocator: std.mem.Allocator, meta_file_path: []const u8) ?[]const u8 {
    const file_path = removeExt(meta_file_path);
    var gltf_file = Gltf.init(allocator, input_dir, file_path, repo_name, removeExt(file_path)) catch |err| return errorString(allocator, "Failed to load gltf file: {}", .{err});
    defer gltf_file.deinit();

    const gltf_dir_path = removeExt((file_path));
    var gltf_dir = output_dir.makeOpenPath(gltf_dir_path, .{}) catch |err| return errorString(allocator, "Failed to open gltf dir: {}", .{err});
    defer gltf_dir.close();

    var wait_group = std.Thread.WaitGroup{};

    const mesh_count = gltf_file.getMeshCount();
    for (0..mesh_count) |i| {
        thread_pool.spawnWg(&wait_group, mesh_thread_worker, .{ &gltf_file, allocator, i });
    }

    const texture_count = gltf_file.getTextureCount();
    for (0..texture_count) |i| {
        thread_pool.spawnWg(&wait_group, texture_thread_worker, .{ &gltf_file, allocator, i });
    }

    const material_count = gltf_file.getMaterialCount();
    for (0..material_count) |i| {
        thread_pool.spawnWg(&wait_group, material_thread_worker, .{ &gltf_file, allocator, i });
    }

    if (gltf_file.gltf_file.data.scene) |default_scene| {
        const scene = gltf_file.loadScene(allocator, default_scene) catch |err| return errorString(allocator, "Failed to load gltf scene: {}", .{err});
        defer scene.deinit(allocator);

        const output_file_path = "scene.json";
        makePath(gltf_dir, output_file_path);

        const output_file = gltf_dir.createFile(output_file_path, .{}) catch |err| return errorString(allocator, "Failed to create file: {}", .{err});
        defer output_file.close();

        var buffer: [1024]u8 = undefined;
        var writer = output_file.writer(&buffer);
        scene.serialize(&writer.interface) catch |err| return errorString(allocator, "Failed to serialize file: {}", .{err});
        writer.interface.flush() catch |err| return errorString(allocator, "Failed to flush file: {}", .{err});
    }

    thread_pool.waitAndWork(&wait_group);

    return null;
}

pub fn loadZonFile(comptime T: type, allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8, options: std.zon.parse.Options) !T {
    const file = try dir.openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAllocOptions(allocator, 1024 * 1024, null, .@"1", 0);
    defer allocator.free(bytes);

    const t = try std.zon.parse.fromSlice(T, allocator, bytes, null, options);
    return t;
}
