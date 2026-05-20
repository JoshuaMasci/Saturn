// Main File for Asset Pipeline

const std = @import("std");
const Progress = std.Progress; //TODO: use this to animate progress like the compiler

const Gltf = @import("asset/gltf.zig");
const AssetType = @import("asset/header.zig").AssetType;
const glsl = @import("asset/glsl.zig");
const io = @import("asset/io.zig");
const Material = @import("asset/material.zig");
const Shader = @import("asset/shader.zig");
const obj = @import("asset/obj.zig");
const stbi = @import("asset/stbi.zig");

pub const ProcessMetaFn = *const fn (allocator: std.mem.Allocator, prog_node: ?std.Progress.Node, meta_file_path: []const u8) anyerror!void;

pub fn thread_worker_meta(process_fn: ProcessMetaFn, prog_node: ?std.Progress.Node, name: []const u8, meta_path: []const u8) void {
    const child_node: ?std.Progress.Node = if (prog_node) |node| node.start(name, 0) else null;
    defer if (child_node) |node| node.end();

    process_fn(global_allocator, child_node, meta_path) catch |err| {
        _ = error_count.fetchAnd(1, .monotonic);
        //TODO: collect errors
        std.log.err("Failed to process {s}: {}", .{ name, err });
    };
}

pub const MetaFileBase = struct {
    type: []const u8,
};

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

    var arena: std.heap.ArenaAllocator = .init(global_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    try thread_pool.init(.{ .allocator = global_allocator });
    defer thread_pool.deinit();

    //Asset Init
    stbi.init(global_allocator);
    defer stbi.deinit();

    try glsl.init();
    defer glsl.deinit();

    var args = std.process.args();
    _ = args.next() orelse std.debug.panic("Failed to read process name, honestly IDK how this happens", .{});
    repo_name = args.next() orelse std.debug.panic("Failed to read asset repo name", .{});
    const input_path = args.next() orelse std.debug.panic("Failed to read input path", .{});
    const output_path = args.next() orelse std.debug.panic("Failed to read output path", .{});

    input_dir = try std.fs.cwd().openDir(input_path, .{ .iterate = true });
    defer input_dir.close();

    try std.fs.cwd().makePath(output_path);
    output_dir = try std.fs.cwd().openDir(output_path, .{});
    defer output_dir.close();

    const progress = std.Progress.start(.{});
    defer progress.end();

    const root_node = progress.start("Assets", 0);
    defer root_node.end();

    var meta_type_process_fns = std.StringHashMap(ProcessMetaFn).init(global_allocator);
    defer meta_type_process_fns.deinit();

    //Shaders
    try meta_type_process_fns.put("shader-dir", processShaderDir);

    //Textures
    try meta_type_process_fns.put("texture", processStb);

    //Materials
    try meta_type_process_fns.put("material", processMaterial);

    //Meshes
    try meta_type_process_fns.put("obj-mesh", processObj);
    try meta_type_process_fns.put("gltf-mesh", processGltf);
    try meta_type_process_fns.put("gltf-mesh", processGltf);

    var wait_group = std.Thread.WaitGroup{};

    var walker = try input_dir.walk(global_allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const meta_file_ext = std.fs.path.extension(entry.basename);
            if (std.mem.eql(u8, meta_file_ext, ".meta")) {
                if (readMetaType(global_allocator, input_dir, entry.path)) |meta_type| {
                    defer global_allocator.free(meta_type);
                    if (meta_type_process_fns.get(meta_type)) |process_fn| {
                        const name = try arena_allocator.dupe(u8, entry.basename);
                        const meta_path = try arena_allocator.dupe(u8, entry.path);
                        thread_pool.spawnWg(&wait_group, thread_worker_meta, .{ process_fn, root_node, name, meta_path });
                    }
                }
            }
        }
    }

    thread_pool.waitAndWork(&wait_group);

    const failed = error_count.load(.monotonic);
    if (failed > 0) {
        std.log.err("Failed to process {} assets", .{failed});
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

fn processObj(allocator: std.mem.Allocator, prog_node: ?std.Progress.Node, meta_file_path: []const u8) !void {
    _ = prog_node; // autofix
    const file_path = removeExt(meta_file_path);

    const processed_mesh = try obj.loadObjMesh(allocator, input_dir, file_path);
    defer processed_mesh.deinit(allocator);

    const new_path = try replaceExt(allocator, file_path, ".asset");
    defer allocator.free(new_path);

    try io.writeFile(output_dir, .mesh, new_path, processed_mesh);
}

fn processStb(allocator: std.mem.Allocator, prog_node: ?std.Progress.Node, meta_file_path: []const u8) !void {
    _ = prog_node; // autofix
    const file_path = removeExt(meta_file_path);

    const texture = try stbi.loadFromFile(allocator, input_dir, std.fs.path.stem(file_path), file_path);
    defer texture.deinit(allocator);

    const new_path = try replaceExt(allocator, file_path, ".asset");
    defer allocator.free(new_path);

    try io.writeFile(output_dir, .texture, new_path, texture);
}

fn processMaterial(allocator: std.mem.Allocator, prog_node: ?std.Progress.Node, meta_file_path: []const u8) !void {
    _ = prog_node; // autofix
    const file_path = removeExt(meta_file_path);

    const json_material = try Material.Json.read(allocator, input_dir, file_path);
    defer json_material.deinit();

    const material = try Material.initFromJson(allocator, &json_material.value);
    defer material.deinit(allocator);

    const new_path = try replaceExt(allocator, file_path, ".asset");
    defer allocator.free(new_path);

    try io.writeFile(output_dir, .material, new_path, material);
}

fn processShaderDir(allocator: std.mem.Allocator, prog_node: ?std.Progress.Node, meta_file_path: []const u8) !void {
    _ = prog_node; // autofix

    const meta_data = try loadZonFile(Shader.DirectoryMeta, allocator, input_dir, meta_file_path, .{ .ignore_unknown_fields = true });
    defer std.zon.parse.free(allocator, meta_data);

    const shader_dir_path = std.fs.path.dirname(meta_file_path) orelse return error.failedToGetDirName;

    var shader_dir = try input_dir.openDir(shader_dir_path, .{ .iterate = true, .access_sub_paths = false });
    defer shader_dir.close();

    var shader_out_dir = try output_dir.makeOpenPath(shader_dir_path, .{});
    defer shader_out_dir.close();

    switch (meta_data.language) {
        .glsl => return processGlslShaderDir(allocator, meta_data, shader_dir, shader_out_dir),
        else => {},
    }
}

fn processGlslShaderDir(allocator: std.mem.Allocator, meta_data: Shader.DirectoryMeta, shader_dir: std.fs.Dir, shader_out_dir: std.fs.Dir) !void {
    _ = meta_data; // autofix
    var local_error_count: usize = 0;

    var walker = try shader_dir.walk(global_allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const shader_ext = std.fs.path.extension(entry.path);
            if (Shader.Stage.getShaderStage(shader_ext)) |stage| {
                const shader_code = shader_dir.readFileAllocOptions(allocator, entry.path, std.math.maxInt(usize), null, .@"4", 0) catch |err| {
                    std.log.err("Failed to read shader {s}: {}", .{ entry.path, err });
                    local_error_count += 1;
                    continue;
                };
                defer allocator.free(shader_code);

                const shader = glsl.compileGlslToSpirv(
                    allocator,
                    shader_dir,
                    entry.basename,
                    shader_code,
                    stage,
                ) catch |err| {
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
        fn run(gltf_file: *Gltf, allocator: std.mem.Allocator, prog_node: ?std.Progress.Node, index: usize) void {
            const name = std.fmt.allocPrint(allocator, "{s}_{}", .{ asset_name, index }) catch |err| std.debug.panic("Failed to alloc name {}", .{err});
            defer allocator.free(name);

            const child_node: ?std.Progress.Node = if (prog_node) |node| node.start(name, 0) else null;
            defer if (child_node) |node| node.end();

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

fn processGltf(allocator: std.mem.Allocator, prog_node: ?std.Progress.Node, meta_file_path: []const u8) !void {
    const file_path = removeExt(meta_file_path);
    var gltf_file = try Gltf.init(allocator, input_dir, file_path, repo_name, removeExt(file_path));
    defer gltf_file.deinit();

    const gltf_dir_path = removeExt((file_path));
    var gltf_dir = try output_dir.makeOpenPath(gltf_dir_path, .{});
    defer gltf_dir.close();

    var wait_group = std.Thread.WaitGroup{};

    const mesh_count = gltf_file.getMeshCount();
    for (0..mesh_count) |i| {
        thread_pool.spawnWg(&wait_group, mesh_thread_worker, .{ &gltf_file, allocator, prog_node, i });
    }

    const texture_count = gltf_file.getTextureCount();
    for (0..texture_count) |i| {
        thread_pool.spawnWg(&wait_group, texture_thread_worker, .{ &gltf_file, allocator, prog_node, i });
    }

    const material_count = gltf_file.getMaterialCount();
    for (0..material_count) |i| {
        thread_pool.spawnWg(&wait_group, material_thread_worker, .{ &gltf_file, allocator, prog_node, i });
    }

    if (gltf_file.gltf_file.data.scene) |default_scene| {
        const scene = try gltf_file.loadScene(allocator, default_scene);
        defer scene.deinit(allocator);

        const output_file_path = "scene.json";
        makePath(gltf_dir, output_file_path);

        const output_file = try gltf_dir.createFile(output_file_path, .{});
        defer output_file.close();

        var buffer: [1024]u8 = undefined;
        var writer = output_file.writer(&buffer);
        try scene.serialize(&writer.interface);
        try writer.interface.flush();
    }

    thread_pool.waitAndWork(&wait_group);
}

pub fn loadZonFile(comptime T: type, allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8, options: std.zon.parse.Options) !T {
    const file = try dir.openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAllocOptions(allocator, 1024 * 1024, null, .@"1", 0);
    defer allocator.free(bytes);

    const t = try std.zon.parse.fromSlice(T, allocator, bytes, null, options);
    return t;
}
